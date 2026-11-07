import asyncio
from types import SimpleNamespace

import pytest
from google.genai import errors, types

from sorted_api.contract import ParseRequest
from sorted_api.parser import GeminiParser, ParseFailed, ParseOutput

REQUEST = ParseRequest(text="get milk", timezone="Asia/Kolkata", now="2026-11-07T10:00:00", list_names=["Groceries"])

MILK = {
    "kind": "shopping_item", "title": "Milk", "due_at": None, "all_day": False, "rrule": None,
    "priority": "normal", "amount": None, "currency": None, "list_name": "Groceries",
    "category": "Dairy", "needs_clarification": None,
}


def response(text: str | None, finish: types.FinishReason | None = types.FinishReason.STOP) -> types.GenerateContentResponse:
    candidates = None
    if finish is not None:
        candidates = [types.Candidate(content=types.Content(role="model", parts=[types.Part(text=text)]), finish_reason=finish)]
    return types.GenerateContentResponse(candidates=candidates)


def milk_reply() -> types.GenerateContentResponse:
    return response(ParseOutput.model_validate({"items": [MILK]}).model_dump_json())


def parser_returning(*replies, **options) -> tuple[GeminiParser, list[dict]]:
    """A parser whose fake client gives one reply per call: a response, an error to raise, or a delay in seconds."""
    calls: list[dict] = []
    pending = list(replies)

    async def generate_content(**kwargs):
        calls.append(kwargs)
        reply = pending.pop(0)
        if isinstance(reply, Exception):
            raise reply
        if isinstance(reply, float):
            await asyncio.sleep(reply)
        return reply

    client = SimpleNamespace(aio=SimpleNamespace(models=SimpleNamespace(generate_content=generate_content)))
    return GeminiParser(client, **options), calls


def busy() -> errors.ServerError:
    return errors.ServerError(503, {"error": {"code": 503, "message": "high demand", "status": "UNAVAILABLE"}})


def test_returns_items_and_sends_the_schema():
    parser, calls = parser_returning(milk_reply())
    items = asyncio.run(parser.parse(REQUEST))
    assert [item.title for item in items] == ["Milk"]
    (call,) = calls
    assert call["model"] == "gemini-3.8-flash"
    assert call["config"].response_mime_type == "application/json"
    assert call["config"].response_json_schema == ParseOutput.model_json_schema()
    assert "<text>\nget milk\n</text>" in call["contents"]


@pytest.mark.parametrize(
    "reply",
    [
        response("{}", finish=types.FinishReason.SAFETY),
        response('{"items": [', finish=types.FinishReason.MAX_TOKENS),
        response(None, finish=None),
        response('{"items": [{"kind": "spaceship"}]}'),
        response("not json"),
    ],
    ids=["safety", "max-tokens", "blocked-prompt", "wrong-shape", "not-json"],
)
def test_unusable_output_fails_cleanly(reply):
    parser, _ = parser_returning(reply)
    with pytest.raises(ParseFailed):
        asyncio.run(parser.parse(REQUEST))


def test_falls_back_when_the_main_model_is_overloaded():
    parser, calls = parser_returning(busy(), milk_reply())
    items = asyncio.run(parser.parse(REQUEST))
    assert [item.title for item in items] == ["Milk"]
    assert [call["model"] for call in calls] == ["gemini-3.8-flash", "gemini-3.6-flash"]


def test_falls_back_when_the_main_model_is_slow():
    parser, calls = parser_returning(5.0, milk_reply(), attempt_seconds=0.05)
    items = asyncio.run(parser.parse(REQUEST))
    assert [item.title for item in items] == ["Milk"]
    assert len(calls) == 2


def test_fails_when_every_model_fails():
    parser, calls = parser_returning(busy(), busy())
    with pytest.raises(ParseFailed, match="gemini-3.8-flash: 503 UNAVAILABLE; gemini-3.6-flash: 503 UNAVAILABLE"):
        asyncio.run(parser.parse(REQUEST))
    assert len(calls) == 2


def test_stops_at_the_time_budget():
    parser, calls = parser_returning(5.0, 5.0, budget_seconds=0.05, attempt_seconds=0.05)
    with pytest.raises(ParseFailed):
        asyncio.run(parser.parse(REQUEST))
    assert len(calls) == 1


def test_bad_output_does_not_try_another_model():
    parser, calls = parser_returning(response("{}", finish=types.FinishReason.SAFETY), milk_reply())
    with pytest.raises(ParseFailed):
        asyncio.run(parser.parse(REQUEST))
    assert len(calls) == 1
