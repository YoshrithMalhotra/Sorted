"""Checks the model's items before they reach the app.

Structured outputs guarantee the shape; this enforces the meaning. A field
that fails a check is dropped rather than failing the whole capture, and the
user gets a question on the card instead.
"""

import re
from datetime import datetime

from . import rrule
from .contract import CaptureKind, ParsedItem

_CURRENCY = re.compile(r"[A-Z]{3}")

ASK_REPEAT = "How often should this repeat?"
ASK_DATE = "When should this be?"
ASK_PAST = "That time has already passed. When should this be?"


def clean(items: list[ParsedItem], now: datetime) -> list[ParsedItem]:
    return [item for item in (_clean_item(item, now) for item in items) if item is not None]


def _clean_item(item: ParsedItem, now: datetime) -> ParsedItem | None:
    item = item.model_copy()
    item.title = item.title.strip()
    if not item.title:
        return None
    questions: list[str] = []

    due = None
    if item.due_at is not None:
        due = _local_datetime(item.due_at)
        if due is None:
            item.due_at = None
            questions.append(ASK_DATE)
        else:
            item.due_at = due.strftime("%Y-%m-%dT%H:%M:%S")

    if item.rrule is not None:
        try:
            item.rrule = rrule.canonical(item.rrule)
        except rrule.RRuleError:
            item.rrule = None
            questions.append(ASK_REPEAT)

    # A one-off in the past is almost always a misread date. A recurring
    # item's start can be past: the app moves it to the next occurrence.
    if due is not None and item.rrule is None:
        passed = due.date() < now.date() if item.all_day else due < now
        if passed:
            questions.append(ASK_PAST)

    if item.kind is CaptureKind.bill:
        if item.amount is not None and item.amount < 0:
            item.amount = None
        if item.currency is not None:
            item.currency = item.currency.strip().upper()
            if not _CURRENCY.fullmatch(item.currency):
                item.currency = None
    else:
        item.amount = None
        item.currency = None

    if item.kind is not CaptureKind.shopping_item:
        item.list_name = None
        item.category = None

    if item.needs_clarification is not None:
        item.needs_clarification = item.needs_clarification.strip() or None
    if item.needs_clarification is None and questions:
        item.needs_clarification = questions[0]
    return item


def _local_datetime(value: str) -> datetime | None:
    """Reads "2026-11-10T09:00:00" or "2026-11-10". An offset is ignored: times are local."""
    try:
        parsed = datetime.fromisoformat(value.strip())
    except ValueError:
        return None
    return parsed.replace(tzinfo=None)
