import pytest
from fastapi.testclient import TestClient

from sorted_api.contract import CaptureKind, ParsedItem, ParseRequest, Priority
from sorted_api.main import app, get_parser
from sorted_api.parser import ParseFailed, user_message
from sorted_api.validate import ASK_PAST, ASK_REPEAT

REQUEST = {
    "text": "pay rent on the 1st, and get milk",
    "timezone": "Asia/Kolkata",
    "locale": "en_IN",
    "now": "2026-11-06T16:30:00",
    "list_names": ["Groceries", "Pharmacy"],
}


def item(kind: CaptureKind, title: str, **fields) -> ParsedItem:
    defaults = dict(
        due_at=None, all_day=False, rrule=None, priority=Priority.normal, amount=None,
        currency=None, list_name=None, category=None, needs_clarification=None,
    )
    return ParsedItem(kind=kind, title=title, **(defaults | fields))


class FakeParser:
    def __init__(self, items: list[ParsedItem] | None = None, error: Exception | None = None) -> None:
        self.items = items or []
        self.error = error
        self.requests: list[ParseRequest] = []

    async def parse(self, request: ParseRequest) -> list[ParsedItem]:
        self.requests.append(request)
        if self.error:
            raise self.error
        return self.items


@pytest.fixture
def client(monkeypatch):
    monkeypatch.delenv("SORTED_CLIENT_KEY", raising=False)
    yield TestClient(app)
    app.dependency_overrides.clear()


def use(parser: FakeParser) -> FakeParser:
    app.dependency_overrides[get_parser] = lambda: parser
    return parser


def test_returns_snake_case_items(client):
    use(FakeParser([
        item(CaptureKind.bill, "Pay rent", due_at="2026-12-01T00:00:00", all_day=True,
             rrule="FREQ=MONTHLY;BYMONTHDAY=1", amount=25000, currency="inr"),
        item(CaptureKind.shopping_item, "Milk", list_name="Groceries", category="Dairy"),
    ]))
    response = client.post("/parse", json=REQUEST)
    assert response.status_code == 200
    bill, milk = response.json()["items"]
    assert bill["kind"] == "bill"
    assert bill["due_at"] == "2026-12-01T00:00:00"
    assert bill["all_day"] is True
    assert bill["currency"] == "INR"
    assert milk["kind"] == "shopping_item"
    assert milk["list_name"] == "Groceries"


def test_drops_a_rule_the_app_cannot_expand(client):
    use(FakeParser([item(CaptureKind.task, "Standup", due_at="2026-11-09T10:00:00", rrule="FREQ=MONTHLY;BYSETPOS=-1")]))
    (task,) = client.post("/parse", json=REQUEST).json()["items"]
    assert task["rrule"] is None
    assert task["needs_clarification"] == ASK_REPEAT


def test_canonicalizes_rules(client):
    use(FakeParser([item(CaptureKind.reminder, "Water plants", due_at="2026-11-07T09:00:00", rrule="RRULE:freq=daily;interval=1")]))
    (reminder,) = client.post("/parse", json=REQUEST).json()["items"]
    assert reminder["rrule"] == "FREQ=DAILY"


def test_asks_about_a_one_off_in_the_past(client):
    use(FakeParser([
        item(CaptureKind.reminder, "Call bank", due_at="2026-11-06T09:00:00"),
        item(CaptureKind.task, "File report", due_at="2026-11-06T00:00:00", all_day=True),
    ]))
    past, today = client.post("/parse", json=REQUEST).json()["items"]
    assert past["needs_clarification"] == ASK_PAST
    assert today["needs_clarification"] is None


def test_strips_fields_that_do_not_belong_to_the_kind(client):
    use(FakeParser([
        item(CaptureKind.task, "Buy gift", amount=50, currency="USD", list_name="Groceries", category="Other"),
        item(CaptureKind.bill, "Electricity", amount=-5, currency="rupees"),
        item(CaptureKind.task, "   "),
    ]))
    task, bill = client.post("/parse", json=REQUEST).json()["items"]
    assert (task["amount"], task["currency"], task["list_name"], task["category"]) == (None, None, None, None)
    assert (bill["amount"], bill["currency"]) == (None, None)


def test_nothing_to_do_returns_no_items(client):
    use(FakeParser([]))
    response = client.post("/parse", json=REQUEST | {"text": "hello"})
    assert response.json() == {"items": []}


def test_parser_failure_is_a_502(client):
    use(FakeParser(error=ParseFailed("boom")))
    assert client.post("/parse", json=REQUEST).status_code == 502


@pytest.mark.parametrize("change", [{"timezone": "Mars/Base"}, {"text": ""}, {"now": "yesterday"}])
def test_rejects_bad_requests(client, change):
    use(FakeParser())
    assert client.post("/parse", json=REQUEST | change).status_code == 422


def test_client_key_is_checked_when_set(client, monkeypatch):
    use(FakeParser())
    monkeypatch.setenv("SORTED_CLIENT_KEY", "secret")
    assert client.post("/parse", json=REQUEST).status_code == 401
    assert client.post("/parse", json=REQUEST, headers={"apikey": "wrong"}).status_code == 401
    assert client.post("/parse", json=REQUEST, headers={"apikey": "secret"}).status_code == 200


def test_request_matches_what_the_ios_app_sends(client):
    # Encoded by ParseRequest in ParseContract.swift with JSONEncoder.api.
    parser = use(FakeParser())
    body = {"text": "call mom", "timezone": "America/New_York", "locale": "en_US",
            "now": "2026-11-06T16:30:00", "list_names": []}
    assert client.post("/parse", json=body).status_code == 200
    message = user_message(parser.requests[0])
    assert "Friday 2026-11-06T16:30:00" in message
    assert "(none yet)" in message



def test_missing_api_key_is_a_502_not_a_crash(client):
    from sorted_api.parser import GeminiParser

    use(GeminiParser(client=None))
    assert client.post("/parse", json=REQUEST).status_code == 502
