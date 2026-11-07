"""OHLCV chart-period aggregation using locally stored daily candles."""

from datetime import date, datetime


def _trading_date(value):
    parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    return parsed.date()


def aggregate_candles(candles, period="daily"):
    """Return daily, ISO-weekly, or calendar-month OHLCV bars.

    Weekly/monthly bars are built only from available daily source candles.
    No missing sessions or prices are synthesized.
    """
    if period not in {"daily", "weekly", "monthly"}:
        raise ValueError("period must be daily, weekly or monthly")
    if not candles:
        return []

    ordered = sorted(candles, key=lambda item: str(item["timestamp"]))
    if period == "daily":
        return [
            {
                "timestamp": str(item["timestamp"]),
                "period_start": _trading_date(item["timestamp"]).isoformat(),
                "period_end": _trading_date(item["timestamp"]).isoformat(),
                "open": float(item["open"]),
                "high": float(item["high"]),
                "low": float(item["low"]),
                "close": float(item["close"]),
                "volume": float(item["volume"]),
                "sources": [str(item.get("source", "unspecified"))],
                "sessions": 1,
            }
            for item in ordered
        ]

    buckets = {}
    for item in ordered:
        trading_day = _trading_date(item["timestamp"])
        if period == "weekly":
            iso = trading_day.isocalendar()
            key = (iso.year, iso.week)
        else:
            key = (trading_day.year, trading_day.month)
        buckets.setdefault(key, []).append((trading_day, item))

    result = []
    for key in sorted(buckets):
        entries = buckets[key]
        first_day, first = entries[0]
        last_day, last = entries[-1]
        sources = sorted({str(item.get("source", "unspecified")) for _, item in entries})
        result.append({
            "timestamp": str(last["timestamp"]),
            "period_start": first_day.isoformat(),
            "period_end": last_day.isoformat(),
            "open": float(first["open"]),
            "high": max(float(item["high"]) for _, item in entries),
            "low": min(float(item["low"]) for _, item in entries),
            "close": float(last["close"]),
            "volume": sum(float(item["volume"]) for _, item in entries),
            "sources": sources,
            "sessions": len(entries),
        })
    return result
