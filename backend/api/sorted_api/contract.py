"""The `POST /parse` contract from the MVP spec.

Written by hand until packages/contracts exists. It must match
apps/ios/Packages/SortedKit/Sources/SortedKit/Capture/ParseContract.swift:
the app sends and reads snake_case JSON.
"""

from datetime import datetime
from enum import StrEnum
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import BaseModel, Field, field_validator


class CaptureKind(StrEnum):
    reminder = "reminder"
    task = "task"
    bill = "bill"
    shopping_item = "shopping_item"


class Priority(StrEnum):
    high = "high"
    normal = "normal"
    low = "low"


class ParseRequest(BaseModel):
    text: str = Field(min_length=1, max_length=2000)
    # IANA time zone, for example "Asia/Kolkata".
    timezone: str
    locale: str = "en_US"
    # The current local time, as "2026-11-06T16:30:00".
    now: datetime
    list_names: list[str] = Field(default_factory=list, max_length=50)

    @field_validator("timezone")
    @classmethod
    def known_timezone(cls, value: str) -> str:
        try:
            ZoneInfo(value)
        except (ZoneInfoNotFoundError, ValueError) as error:
            raise ValueError(f"unknown time zone {value!r}") from error
        return value

    @field_validator("now")
    @classmethod
    def local_time(cls, value: datetime) -> datetime:
        # The app sends local wall-clock time; drop any offset so comparisons stay local.
        return value.replace(tzinfo=None)


class ParsedItem(BaseModel):
    """One reminder, task, bill or shopping item taken from the user's sentence."""

    # Every field is required (nullable where optional), so the structured
    # output schema the model fills is strict.
    kind: CaptureKind
    title: str
    # Local date-time of the first occurrence, without an offset.
    due_at: str | None
    # True when no time was given; the app uses the default reminder time.
    all_day: bool
    rrule: str | None
    priority: Priority
    amount: float | None
    # ISO 4217 code.
    currency: str | None
    list_name: str | None
    # The aisle, for shopping items.
    category: str | None
    needs_clarification: str | None


class ParseResponse(BaseModel):
    items: list[ParsedItem]
