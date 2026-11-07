from datetime import datetime
from typing import Literal
from pydantic import BaseModel, Field, field_validator


Exchange = Literal["HOSE", "HNX", "UPCOM"]


class SymbolCreate(BaseModel):
    symbol: str = Field(min_length=3, max_length=12, pattern=r"^[A-Z0-9.]+$")
    name: str = Field(min_length=1, max_length=160)
    exchange: Exchange
    sector: str | None = Field(default=None, max_length=120)


class Candle(BaseModel):
    timestamp: datetime
    open: float = Field(ge=0)
    high: float = Field(ge=0)
    low: float = Field(ge=0)
    close: float = Field(ge=0)
    volume: float = Field(ge=0)

    @field_validator("high")
    @classmethod
    def high_must_cover_prices(cls, value, info):
        low = info.data.get("low")
        if low is not None and value < low:
            raise ValueError("high must be greater than or equal to low")
        return value


class CandleOut(Candle):
    source: str
