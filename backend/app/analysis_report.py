"""Deterministic combined technical report assembled from sourced OHLCV candles."""

from . import price_action, fibonacci, elliott, volume_flow, indicators


def build_analysis_report(candles):
    if not candles:
        raise ValueError("At least one candle is required")
    highs = [float(c["high"]) for c in candles]
    lows = [float(c["low"]) for c in candles]
    closes = [float(c["close"]) for c in candles]
    volumes = [float(c["volume"]) for c in candles]
    timestamps = [c["timestamp"] for c in candles]
    close = closes[-1]

    trend = price_action.analyze_price_action(highs, lows, closes, volumes, timestamps)
    fib = fibonacci.analyze_fibonacci(highs, lows, closes, timestamps)
    wave = elliott.analyze_elliott(highs, lows, closes, timestamps)
    flow = volume_flow.analyze_volume_flow(highs, lows, closes, volumes, timestamps)
    macd = indicators.macd(closes)
    rsi = indicators.rsi(closes, 14)
    ema20 = indicators.ema(closes, 20)
    ema50 = indicators.ema(closes, 50)
    atr14 = indicators.atr(highs, lows, closes, 14)

    latest_indicators = {
        "rsi14": round(rsi[-1], 4) if rsi[-1] is not None else None,
        "macd": round(macd["macd"][-1], 4) if macd["macd"][-1] is not None else None,
        "macd_signal": round(macd["signal"][-1], 4) if macd["signal"][-1] is not None else None,
        "ema20": round(ema20[-1], 4) if ema20[-1] is not None else None,
        "ema50": round(ema50[-1], 4) if ema50[-1] is not None else None,
        "atr14": round(atr14[-1], 4) if atr14[-1] is not None else None,
    }

    supports = trend.get("price_zones", {}).get("supports", [])
    resistances = trend.get("price_zones", {}).get("resistances", [])
    support = supports[0]["price"] if supports else None
    resistance = resistances[0]["price"] if resistances else trend.get("breakout", {}).get("prior_20_bar_high")
    breakout_state = trend.get("breakout", {}).get("state", "unknown")
    trend_state = trend.get("trend", {}).get("classification", "unknown")
    flow_state = flow.get("classification", "unknown")

    bullish_evidence = []
    bearish_evidence = []
    if trend_state == "uptrend":
        bullish_evidence.append("EMA20/EMA50 และ vị trí giá đang nghiêng về xu hướng tăng")
    elif trend_state == "downtrend":
        bearish_evidence.append("EMA20/EMA50 và vị trí giá đang nghiêng về xu hướng giảm")
    if breakout_state == "confirmed_bullish":
        bullish_evidence.append("Breakout vượt biên 20 nến có xác nhận volume")
    elif breakout_state == "confirmed_bearish":
        bearish_evidence.append("Breakdown thủng biên 20 nến có xác nhận volume")
    if flow_state == "accumulation_candidate":
        bullish_evidence.append("CMF và OBV cùng đạt điều kiện ứng viên tích lũy")
    elif flow_state == "distribution_candidate":
        bearish_evidence.append("CMF và OBV cùng đạt điều kiện ứng viên phân phối")

    scenarios = [
        {
            "name": "bullish",
            "label": "Kịch bản tăng",
            "status": "supported" if bullish_evidence else "conditional",
            "evidence": bullish_evidence,
            "confirmation": (
                f"Đóng cửa vượt vùng kháng cự tham chiếu {resistance} với volume xác nhận; "
                "duy trì cấu trúc đáy sau cao hơn đáy trước."
                if resistance is not None else
                "Chờ hình thành vùng kháng cự có dữ liệu pivot xác nhận và breakout kèm volume."
            ),
            "invalidation": (
                f"Đóng cửa thủng vùng hỗ trợ tham chiếu {support}."
                if support is not None else
                "Đóng cửa phá đáy pivot gần nhất đã xác nhận."
            ),
        },
        {
            "name": "base",
            "label": "Kịch bản cơ sở",
            "status": "active" if breakout_state in ("inside_range", "testing_support", "testing_resistance") else "conditional",
            "evidence": [
                f"Trạng thái breakout hiện tại: {breakout_state}",
                f"Phân loại xu hướng hiện tại: {trend_state}",
            ],
            "confirmation": "Giá tiếp tục dao động trong vùng hỗ trợ/kháng cự; chờ đóng cửa xác nhận phá vỡ một phía.",
            "invalidation": "Đóng cửa vượt kháng cự hoặc thủng hỗ trợ với biên độ và volume xác nhận theo bộ quy tắc breakout.",
        },
        {
            "name": "bearish",
            "label": "Kịch bản giảm",
            "status": "supported" if bearish_evidence else "conditional",
            "evidence": bearish_evidence,
            "confirmation": (
                f"Đóng cửa thủng vùng hỗ trợ tham chiếu {support} với volume xác nhận."
                if support is not None else
                "Chờ hình thành vùng hỗ trợ từ pivot xác nhận và breakdown kèm volume."
            ),
            "invalidation": (
                f"Đóng cửa vượt vùng kháng cự tham chiếu {resistance}."
                if resistance is not None else
                "Đóng cửa vượt đỉnh pivot gần nhất đã xác nhận."
            ),
        },
    ]

    return {
        "status": "ok",
        "as_of": timestamps[-1],
        "bars_available": len(candles),
        "latest_close": close,
        "indicators": latest_indicators,
        "trend_and_price_action": trend,
        "fibonacci": fib,
        "elliott": wave,
        "volume_flow": flow,
        "scenarios": scenarios,
        "data_quality": {
            "sources": sorted({str(c.get("source", "unspecified")) for c in candles}),
            "price_adjustment": "unknown",
            "note": "Báo cáo chỉ dùng OHLCV đã lưu; trạng thái điều chỉnh corporate action chưa được xác minh.",
        },
        "interpretation_policy": [
            "Đây là báo cáo kỹ thuật xác định, không phải khuyến nghị mua bán.",
            "Kịch bản supported chỉ phản ánh bằng chứng quy tắc hiện có, không phải xác suất thành công.",
            "Elliott là giả thuyết cấu trúc; rule score không phải xác suất.",
            "Nếu dữ liệu thiếu, từng mô-đun giữ trạng thái insufficient/incomplete thay vì tự tạo dữ liệu.",
        ],
    }
