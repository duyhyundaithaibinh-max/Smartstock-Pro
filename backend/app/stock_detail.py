"""Deterministic stock detail snapshot from locally stored OHLCV candles."""

from . import indicators, price_action


def build_stock_detail(symbol, metadata, candles, timeframe="1d"):
    if not metadata:
        raise ValueError("Unknown symbol")
    ordered = list(candles)
    if not ordered:
        return {
            "symbol": symbol.upper(),
            "timeframe": timeframe,
            "status": "no_data",
            "instrument": metadata,
            "latest": None,
            "indicators": {},
            "trend_and_zones": {
                "status": "insufficient_data",
                "message": "Chưa có dữ liệu OHLCV để phân tích.",
            },
            "liquidity": {
                "status": "insufficient_data",
                "average_traded_value_20_sessions": None,
                "method": "close * volume, arithmetic mean of available recent sessions",
                "note": "Giá trị giao dịch ước tính từ OHLCV, không phải số liệu thanh khoản chính thức của sở.",
            },
            "data_quality": {
                "sources": [],
                "as_of": None,
                "price_adjustment": "unknown",
            },
        }

    highs = [float(item["high"]) for item in ordered]
    lows = [float(item["low"]) for item in ordered]
    closes = [float(item["close"]) for item in ordered]
    volumes = [float(item["volume"]) for item in ordered]
    latest = ordered[-1]
    rsi_values = indicators.rsi(closes, 14)
    macd_values = indicators.macd(closes)
    ema20_values = indicators.ema(closes, 20)
    ema50_values = indicators.ema(closes, 50)
    atr_values = indicators.atr(highs, lows, closes, 14)
    obv_values = indicators.obv(closes, volumes)

    def last(values):
        value = values[-1] if values else None
        return round(float(value), 6) if value is not None else None

    atr_value = last(atr_values)
    close = float(latest["close"])
    recent = ordered[-20:]
    traded_values = [float(item["close"]) * float(item["volume"]) for item in recent]
    liquidity_ready = len(recent) == 20
    sources = sorted({str(item.get("source", "unspecified")) for item in ordered})
    if len(ordered) >= 20:
        trend = price_action.analyze_price_action(
            highs, lows, closes, volumes,
            timestamps=[item["timestamp"] for item in ordered],
        )
    else:
        trend = {
            "status": "insufficient_data",
            "bars_available": len(ordered),
            "bars_required": 20,
            "message": "Cần tối thiểu 20 nến để xác định xu hướng và vùng giá.",
        }

    return {
        "symbol": symbol.upper(),
        "timeframe": timeframe,
        "status": "ok",
        "instrument": metadata,
        "latest": {
            "timestamp": latest["timestamp"],
            "open": float(latest["open"]),
            "high": float(latest["high"]),
            "low": float(latest["low"]),
            "close": close,
            "volume": float(latest["volume"]),
            "source": str(latest.get("source", "unspecified")),
        },
        "indicators": {
            "rsi14": last(rsi_values),
            "macd": last(macd_values["macd"]),
            "macd_signal": last(macd_values["signal"]),
            "macd_histogram": last(macd_values["histogram"]),
            "ema20": last(ema20_values),
            "ema50": last(ema50_values),
            "atr14": atr_value,
            "atr_percent": round(atr_value / close * 100, 4) if atr_value is not None and close else None,
            "obv": last(obv_values),
            "bars_available": len(ordered),
        },
        "trend_and_zones": trend,
        "liquidity": {
            "status": "ok" if liquidity_ready else "insufficient_data",
            "sessions_used": len(recent),
            "sessions_required": 20,
            "average_traded_value_20_sessions": round(sum(traded_values) / len(traded_values), 2) if liquidity_ready else None,
            "latest_traded_value_estimate": round(close * float(latest["volume"]), 2),
            "method": "close * volume; 20-session arithmetic mean",
            "note": "Giá trị giao dịch ước tính từ OHLCV, không phải số liệu thanh khoản chính thức của sở; đơn vị phụ thuộc đơn vị giá và khối lượng của nguồn.",
        },
        "data_quality": {
            "sources": sources,
            "as_of": latest["timestamp"],
            "price_adjustment": "unknown",
            "note": "Chưa xác minh điều chỉnh cổ tức, thưởng cổ phiếu hoặc quyền mua.",
        },
    }
