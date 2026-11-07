"""The RFC 5545 subset Sorted supports, checked the same way the iOS app checks it.

This mirrors `RecurrenceRule.init(_:)` in
apps/ios/Packages/SortedKit/Sources/SortedKit/Recurrence/RecurrenceRule.swift.
A rule that passes here is one the app can expand, so a rule the model writes
never reaches a device that would reject it. Keep the two in step.
"""

import re
from dataclasses import dataclass, field
from datetime import datetime

FREQUENCIES = ("HOURLY", "DAILY", "WEEKLY", "MONTHLY", "YEARLY")
WEEKDAYS = ("MO", "TU", "WE", "TH", "FR", "SA", "SU")
_INTEGER = re.compile(r"[+-]?\d+")


class RRuleError(ValueError):
    pass


@dataclass
class RecurrenceRule:
    frequency: str
    interval: int = 1
    by_day: list[str] = field(default_factory=list)
    by_month_day: list[int] = field(default_factory=list)
    by_month: list[int] = field(default_factory=list)
    by_hour: list[int] = field(default_factory=list)
    until: str | None = None
    count: int | None = None

    def __str__(self) -> str:
        """The canonical form, in the same field order as the app writes it."""
        parts = [f"FREQ={self.frequency}"]
        if self.interval != 1:
            parts.append(f"INTERVAL={self.interval}")
        if self.by_month:
            parts.append("BYMONTH=" + ",".join(map(str, self.by_month)))
        if self.by_month_day:
            parts.append("BYMONTHDAY=" + ",".join(map(str, self.by_month_day)))
        if self.by_day:
            parts.append("BYDAY=" + ",".join(self.by_day))
        if self.by_hour:
            parts.append("BYHOUR=" + ",".join(map(str, self.by_hour)))
        if self.count is not None:
            parts.append(f"COUNT={self.count}")
        if self.until is not None:
            parts.append(f"UNTIL={self.until}")
        return ";".join(parts)


def parse(rule: str) -> RecurrenceRule:
    """Parses `FREQ=MONTHLY;BYMONTHDAY=5`, with or without an `RRULE:` prefix."""
    body = rule.strip()
    if body.upper().startswith("RRULE:"):
        body = body[6:]
    if not body:
        raise RRuleError("empty rule")

    values: dict[str, str] = {}
    for part in filter(None, body.split(";")):
        key, sep, value = part.partition("=")
        if not sep:
            raise RRuleError(f"expected KEY=VALUE, got {part}")
        key, value = key.upper(), value.upper()
        if key in values:
            raise RRuleError(f"{key} appears twice")
        values[key] = value

    rule_obj = RecurrenceRule(frequency="")
    for key, value in values.items():
        match key:
            case "FREQ":
                if value not in FREQUENCIES:
                    raise RRuleError(f"unsupported FREQ={value}")
                rule_obj.frequency = value
            case "INTERVAL":
                rule_obj.interval = _integer(value, key)
            case "COUNT":
                rule_obj.count = _integer(value, key)
            case "UNTIL":
                rule_obj.until = _until(value)
            case "BYDAY":
                rule_obj.by_day = [_weekday_num(token) for token in value.split(",") if token]
            case "BYMONTHDAY":
                rule_obj.by_month_day = _integer_list(value, key)
            case "BYMONTH":
                rule_obj.by_month = _integer_list(value, key)
            case "BYHOUR":
                rule_obj.by_hour = _integer_list(value, key)
            case "WKST":
                if value != "MO":
                    raise RRuleError(f"unsupported WKST={value}")
            case _:
                raise RRuleError(f"unsupported {key}")

    if not rule_obj.frequency:
        raise RRuleError("FREQ is required")
    _validate(rule_obj)
    return rule_obj


def canonical(rule: str) -> str:
    return str(parse(rule))


def _validate(rule: RecurrenceRule) -> None:
    if rule.interval < 1:
        raise RRuleError("INTERVAL must be at least 1")
    if rule.count is not None and rule.count < 1:
        raise RRuleError("COUNT must be at least 1")
    if rule.count is not None and rule.until is not None:
        raise RRuleError("UNTIL and COUNT can't both be set")
    for day in rule.by_month_day:
        if day == 0 or not -31 <= day <= 31:
            raise RRuleError(f"BYMONTHDAY={day}")
    for month in rule.by_month:
        if not 1 <= month <= 12:
            raise RRuleError(f"BYMONTH={month}")
    for hour in rule.by_hour:
        if not 0 <= hour <= 23:
            raise RRuleError(f"BYHOUR={hour}")
    for entry in rule.by_day:
        if len(entry) == 2:
            continue
        if rule.frequency not in ("MONTHLY", "YEARLY"):
            raise RRuleError("BYDAY ordinals need FREQ=MONTHLY or YEARLY")
        ordinal = int(entry[:-2])
        if ordinal == 0 or not -5 <= ordinal <= 5:
            raise RRuleError(f"BYDAY={entry}")
    # "The 20th Monday of the year": valid RFC 5545, but no household phrase needs it.
    if rule.frequency == "YEARLY" and rule.by_day and not rule.by_month:
        raise RRuleError("YEARLY with BYDAY needs BYMONTH")


def _integer(value: str, key: str) -> int:
    if not _INTEGER.fullmatch(value):
        raise RRuleError(f"{key}={value}")
    return int(value)


def _integer_list(value: str, key: str) -> list[int]:
    numbers = [_integer(token, key) for token in value.split(",") if token]
    if not numbers:
        raise RRuleError(f"{key} is empty")
    return numbers


def _weekday_num(token: str) -> str:
    """Normalizes a BYDAY entry such as `-1FR` or `+2TU`."""
    weekday, prefix = token[-2:], token[:-2]
    if len(token) < 2 or weekday not in WEEKDAYS:
        raise RRuleError(f"BYDAY={token}")
    if not prefix:
        return weekday
    return f"{_integer(prefix, 'BYDAY')}{weekday}"


def _until(value: str) -> str:
    """Accepts `20260310`, `20260310T180000` and `20260310T180000Z`."""
    formats = {8: "%Y%m%d", 15: "%Y%m%dT%H%M%S", 16: "%Y%m%dT%H%M%SZ"}
    pattern = formats.get(len(value))
    if pattern is None or not re.fullmatch(r"\d{8}(T\d{6}Z?)?", value):
        raise RRuleError(f"UNTIL={value}")
    try:
        datetime.strptime(value, pattern)
    except ValueError as error:
        raise RRuleError(f"UNTIL={value}") from error
    return value
