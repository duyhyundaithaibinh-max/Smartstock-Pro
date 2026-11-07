from datetime import datetime, timedelta, timezone
import math
import re
from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator


Exchange = Literal["HOSE", "HNX", "UPCOM"]
VIETNAM_TZ = timezone(timedelta(hours=7))


class SymbolCreate(BaseModel):
    symbol: str = Field(min_length=3, max_length=12, pattern=r"^[A-Z0-9.]+$")
    name: str = Field(min_length=1, max_length=160)
    exchange: Exchange
    sector: str | None = Field(default=None, max_length=120)


class Candle(BaseModel):
    """One OHLCV bar. Date-only values mean a Vietnam exchange trading date."""

    timestamp: datetime
    open: float = Field(ge=0, allow_inf_nan=False)
    high: float = Field(ge=0, allow_inf_nan=False)
    low: float = Field(ge=0, allow_inf_nan=False)
    close: float = Field(ge=0, allow_inf_nan=False)
    volume: float = Field(ge=0, allow_inf_nan=False)

    @field_validator("timestamp", mode="before")
    @classmethod
    def normalize_timestamp(cls, value):
        if isinstance(value, str) and re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", value):
            # Daily CSV dates are exchange-local calendar dates, not UTC instants.
            value = datetime.fromisoformat(value).replace(tzinfo=VIETNAM_TZ)
        elif isinstance(value, datetime) and value.tzinfo is None:
            raise ValueError("timestamp must include a timezone offset; use YYYY-MM-DD for a Vietnam trading date")
        elif isinstance(value, str):
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
            if parsed.tzinfo is None:
                raise ValueError("timestamp must include a timezone offset; use YYYY-MM-DD for a Vietnam trading date")
            value = parsed
        if isinstance(value, datetime):
            return value.astimezone(VIETNAM_TZ)
        return value

    @model_validator(mode="after")
    def validate_ohlcv(self):
        values = (self.open, self.high, self.low, self.close, self.volume)
        if any(not math.isfinite(value) for value in values):
            raise ValueError("OHLCV values must be finite numbers")
        if self.high < max(self.open, self.close, self.low):
            raise ValueError("high must be greater than or equal to open, close, and low")
        if self.low > min(self.open, self.close, self.high):
            raise ValueError("low must be less than or equal to open, close, and high")
        return self


class CandleOut(Candle):
    source: str
