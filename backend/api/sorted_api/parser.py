"""Turns one sentence into items with a single Gemini call."""

import asyncio
import logging
import time
from collections.abc import Sequence
from typing import Protocol

import httpx2
from google import genai
from google.genai import errors, types
from pydantic import BaseModel, ValidationError

from .contract import ParsedItem, ParseRequest

log = logging.getLogger(__name__)

# The system prompt and the schema never change between calls, so Gemini's
# implicit caching can reuse them. Everything that varies (the time, the
# lists, the text) goes in the user message.
SYSTEM_PROMPT = """\
You turn one sentence from the user of Sorted, a life-admin app, into the \
items it asks for. The app shows each item as a card the user confirms, so \
make your best guess and use needs_clarification only when a guess would \
probably be wrong.

Kinds
- reminder: something to be notified about at a time, such as a call, an \
appointment, or anything phrased "remind me to".
- task: a to-do or a deadline, such as "renew car insurance before March 10". \
A deadline goes in due_at.
- bill: a payment or subscription, usually recurring, such as rent, \
electricity or Netflix.
- shopping_item: something to buy. Make one item per product.

One sentence often holds several items: "call mom Sunday evening, renew car \
insurance before March 10, and get milk, eggs and dish soap" is one reminder, \
one task and three shopping items. If the text is not a request at all \
("hello", "thanks"), return no items.

Fields
- title: short and imperative, without the date or repeat words: "Call mom", \
"Pay electricity bill". For shopping, the product name with any quantity: \
"Milk", "2 kg rice".
- due_at: the first occurrence as a local date-time "YYYY-MM-DDTHH:MM:SS" \
with no offset, worked out from the current local time you are given. It is \
never in the past: "Sunday" is the next Sunday, and a date that has passed \
this year means next year. null when the text gives no date. Shopping items \
are always null.
- all_day: true when a date is given but no time; then due_at uses T00:00:00 \
and the app applies the user's default reminder time. Rough times are not \
all-day: morning is 09:00, afternoon 14:00, evening 18:00, tonight and night \
20:00.
- rrule: an RFC 5545 rule, without "RRULE:", when the item repeats; otherwise \
null. Only this subset is allowed:
  FREQ=HOURLY, DAILY, WEEKLY, MONTHLY or YEARLY; INTERVAL; BYDAY (MO,TU,...; \
an ordinal such as 2TU or -1FR only with MONTHLY or YEARLY); BYMONTHDAY \
(-1 is the last day); BYMONTH; BYHOUR; COUNT or UNTIL (YYYYMMDD), never both.
  No BYSETPOS, BYMINUTE, BYYEARDAY, BYWEEKNO or WKST other than MO. YEARLY \
with BYDAY must also have BYMONTH.
  Examples: "on the 5th of every month" FREQ=MONTHLY;BYMONTHDAY=5. "end of \
the month" FREQ=MONTHLY;BYMONTHDAY=-1, never 31. "last Friday of the month" \
FREQ=MONTHLY;BYDAY=-1FR. "every other Tuesday" FREQ=WEEKLY;INTERVAL=2;BYDAY=TU. \
"weekdays" FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR. "every 2 hours from 9 to 6" \
FREQ=HOURLY;INTERVAL=2;BYHOUR=9,11,13,15,17. "every March 10" \
FREQ=YEARLY;BYMONTH=3;BYMONTHDAY=10.
  For a repeating item, due_at is the first occurrence that matches the rule.
- priority: high only when the text says it is urgent or important, low when \
it says it can wait, otherwise normal.
- amount and currency: bills only, otherwise null. amount is a plain number. \
currency is an ISO 4217 code; when only a symbol or nothing is given, infer it \
from the locale ("$" with en_US is USD, "rs" or "₹" is INR). null when no \
amount is given.
- list_name: shopping items only. Use the user's list that fits best (medicine \
goes to a pharmacy list if they have one), matching its name exactly; \
otherwise their first list. null for other kinds.
- category: shopping items only, the aisle: Produce, Dairy, Bakery, \
Meat & Fish, Pantry, Frozen, Drinks, Household, Personal Care, Pharmacy or \
Other. null for other kinds.
- needs_clarification: one short question for the user when something \
important is ambiguous, such as "Which day is the dentist appointment?"; \
otherwise null.
"""


class ParseOutput(BaseModel):
    items: list[ParsedItem]


class ParseFailed(Exception):
    """The model could not produce items. The app keeps the text as a plain task."""


class Parser(Protocol):
    async def parse(self, request: ParseRequest) -> list[ParsedItem]: ...


def user_message(request: ParseRequest) -> str:
    lists = ", ".join(request.list_names) if request.list_names else "(none yet)"
    return (
        f"Current local time: {request.now.strftime('%A %Y-%m-%dT%H:%M:%S')}\n"
        f"Time zone: {request.timezone}\n"
        f"Locale: {request.locale}\n"
        f"Shopping lists: {lists}\n\n"
        f"<text>\n{request.text}\n</text>"
    )


class GeminiParser:
    """Calls the first model, and the next one when a call fails outright.

    Google returns 503 "high demand" or 504 for one model while others answer
    fine, so a backup model keeps capture working. Every attempt shares one
    time budget because the app gives up after 15 seconds.
    """

    def __init__(
        self,
        client: genai.Client | None,
        model: str = "gemini-3.8-flash",
        fallback_models: Sequence[str] = ("gemini-3.6-flash",),
        thinking_level: str = "low",
        budget_seconds: float = 14,
        # The most one attempt may take while a backup model is still waiting.
        attempt_seconds: float = 8,
    ) -> None:
        self.client = client
        self.models = [model, *(name for name in fallback_models if name != model)]
        self.budget_seconds = budget_seconds
        self.attempt_seconds = attempt_seconds
        self.config = types.GenerateContentConfig(
            system_instruction=SYSTEM_PROMPT,
            response_mime_type="application/json",
            response_json_schema=ParseOutput.model_json_schema(),
            thinking_config=types.ThinkingConfig(thinking_level=thinking_level.upper()),
        )
        if client is None:
            log.warning("No Gemini API key: set GEMINI_API_KEY in .env. /parse will fail until then.")

    async def parse(self, request: ParseRequest) -> list[ParsedItem]:
        if self.client is None:
            raise ParseFailed("no Gemini API key")
        started = time.monotonic()
        failures: list[str] = []
        for index, model in enumerate(self.models):
            remaining = self.budget_seconds - (time.monotonic() - started)
            if remaining <= 0:
                break
            last = index == len(self.models) - 1
            try:
                async with asyncio.timeout(remaining if last else min(remaining, self.attempt_seconds)):
                    response = await self.client.aio.models.generate_content(
                        model=model,
                        contents=user_message(request),
                        config=self.config,
                    )
            except (errors.APIError, httpx2.HTTPError, TimeoutError) as error:
                failures.append(f"{model}: {_describe(error)}")
                log.warning("parse model=%s failed: %s", model, _describe(error))
                continue
            return self._items(model, response, started)
        raise ParseFailed("Gemini API error: " + "; ".join(failures or ["out of time"]))

    def _items(self, model: str, response: types.GenerateContentResponse, started: float) -> list[ParsedItem]:
        candidate = response.candidates[0] if response.candidates else None
        finish = candidate.finish_reason if candidate else None
        usage = response.usage_metadata
        log.info(
            "parse model=%s finish=%s input=%s cached=%s thinking=%s output=%s ms=%d",
            model,
            finish,
            usage and usage.prompt_token_count,
            usage and usage.cached_content_token_count,
            usage and usage.thoughts_token_count,
            usage and usage.candidates_token_count,
            (time.monotonic() - started) * 1000,
        )
        if finish != types.FinishReason.STOP:
            # SAFETY, MAX_TOKENS, a blocked prompt (no candidates) and the rest.
            raise ParseFailed(f"no usable output (finish_reason={finish})")
        try:
            return ParseOutput.model_validate_json(response.text or "").items
        except ValidationError as error:
            raise ParseFailed(f"output did not match the schema: {error}") from error


def _describe(error: Exception) -> str:
    if isinstance(error, errors.APIError):
        return f"{error.code} {error.status}"
    if isinstance(error, TimeoutError):
        return "timed out"
    return type(error).__name__
