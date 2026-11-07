import pytest

from sorted_api import rrule

# The same cases as RecurrenceRuleTests.swift, so the server and the app agree.


@pytest.mark.parametrize(
    ("given", "expected"),
    [
        ("FREQ=MONTHLY;BYMONTHDAY=5", "FREQ=MONTHLY;BYMONTHDAY=5"),
        ("RRULE:FREQ=MONTHLY;BYDAY=-1FR", "FREQ=MONTHLY;BYDAY=-1FR"),
        ("freq=weekly;interval=2;byday=TU", "FREQ=WEEKLY;INTERVAL=2;BYDAY=TU"),
        ("FREQ=DAILY;COUNT=5;INTERVAL=1", "FREQ=DAILY;COUNT=5"),
        ("FREQ=YEARLY;BYMONTH=3;BYMONTHDAY=10;UNTIL=20300310", "FREQ=YEARLY;BYMONTH=3;BYMONTHDAY=10;UNTIL=20300310"),
        ("FREQ=DAILY;UNTIL=20261231T183000Z", "FREQ=DAILY;UNTIL=20261231T183000Z"),
        ("FREQ=HOURLY;INTERVAL=2;BYHOUR=9,11,13,15,17;WKST=MO", "FREQ=HOURLY;INTERVAL=2;BYHOUR=9,11,13,15,17"),
    ],
)
def test_round_trips_to_a_canonical_string(given: str, expected: str) -> None:
    assert rrule.canonical(given) == expected


@pytest.mark.parametrize(
    "given",
    [
        "",
        "BYDAY=MO",
        "FREQ=DAILY;INTERVAL=0",
        "FREQ=DAILY;COUNT=2;UNTIL=20270101",
        "FREQ=MONTHLY;BYMONTHDAY=0",
        "FREQ=MONTHLY;BYMONTHDAY=32",
        "FREQ=WEEKLY;BYDAY=1MO",
        "FREQ=MONTHLY;BYDAY=6MO",
        "FREQ=DAILY;FREQ=WEEKLY",
        "FREQ=DAILY;UNTIL=2027",
    ],
)
def test_rejects_malformed_rules(given: str) -> None:
    with pytest.raises(rrule.RRuleError):
        rrule.parse(given)


@pytest.mark.parametrize(
    "given",
    [
        "FREQ=MINUTELY",
        "FREQ=WEEKLY;WKST=SU",
        "FREQ=YEARLY;BYDAY=MO",
        "FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1",
    ],
)
def test_rejects_rules_outside_the_supported_subset(given: str) -> None:
    with pytest.raises(rrule.RRuleError):
        rrule.parse(given)


@pytest.mark.parametrize("given", ["FREQ=DAILY;UNTIL=20261332", "FREQ=DAILY;INTERVAL=1_0", "FREQ=WEEKLY;BYDAY=XX"])
def test_rejects_values_the_app_cannot_read(given: str) -> None:
    with pytest.raises(rrule.RRuleError):
        rrule.parse(given)
