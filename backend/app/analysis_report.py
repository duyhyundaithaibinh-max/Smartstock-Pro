"""Deterministic combined technical report assembled from sourced OHLCV candles."""

from . import price_action, fibonacci, elliott, volume_flow, indicators


def build_analysis_report(candles, rule_config=None, rule_version="1.0.0", rule_config_sha256=None):
    if not candles:
        raise ValueError("At least one candle is required")
    highs = [float(c["high"]) for c in candles]
    lows = [float(c["low"]) for c in candles]
    closes = [float(c["close"]) for c in candles]
    volumes = [float(c["volume"]) for c in candles]
    timestamps = [c["timestamp"] for c in candles]
    close = closes[-1]
    rule_config = rule_config or {}
    price_action_rules = rule_config.get("price_action", {})
    fibonacci_rules = rule_config.get("fibonacci", {})
    elliott_rules = rule_config.get("elliott", {})
    volume_rules = rule_config.get("volume_flow", {})
    indicator_rules = rule_config.get("indicators", {})
    ema_fast_period = indicator_rules.get("ema_fast_period", 20)
    ema_slow_period = indicator_rules.get("ema_slow_period", 50)

    trend = price_action.analyze_price_action(
        highs, lows, closes, volumes, timestamps,
        lookback=price_action_rules.get("lookback", 120),
        wing=price_action_rules.get("wing", 2),
        range_lookback=price_action_rules.get("range_lookback", 20),
        volume_confirmation_pct=price_action_rules.get("volume_confirmation_pct", 120),
        breakout_buffer_atr_pct=price_action_rules.get("breakout_buffer_atr_pct", 20),
        ema_fast_period=ema_fast_period,
        ema_slow_period=ema_slow_period,
    )
    fib = fibonacci.analyze_fibonacci(
        highs, lows, closes, timestamps,
        lookback=fibonacci_rules.get("lookback", 250),
        wing=fibonacci_rules.get("wing", 2),
    )
    wave = elliott.analyze_elliott(
        highs, lows, closes, timestamps,
        lookback=elliott_rules.get("lookback", 250),
        wing=elliott_rules.get("wing", 2),
    )
    flow = volume_flow.analyze_volume_flow(
        highs, lows, closes, volumes, timestamps,
        window=volume_rules.get("window", 20),
    )
    rsi_period = indicator_rules.get("rsi_period", 14)
    macd_fast_period = indicator_rules.get("macd_fast_period", 12)
    macd_slow_period = indicator_rules.get("macd_slow_period", 26)
    macd_signal_period = indicator_rules.get("macd_signal_period", 9)
    atr_period = indicator_rules.get("atr_period", 14)
    macd = indicators.macd(closes, macd_fast_period, macd_slow_period, macd_signal_period)
    rsi = indicators.rsi(closes, rsi_period)
    ema_fast = indicators.ema(closes, ema_fast_period)
    ema_slow = indicators.ema(closes, ema_slow_period)
    atr_value = indicators.atr(highs, lows, closes, atr_period)

    latest_indicators = {
        "rsi": round(rsi[-1], 4) if rsi[-1] is not None else None,
        "rsi_period": rsi_period,
        "rsi14": round(rsi[-1], 4) if rsi_period == 14 and rsi[-1] is not None else None,
        "macd": round(macd["macd"][-1], 4) if macd["macd"][-1] is not None else None,
        "macd_signal": round(macd["signal"][-1], 4) if macd["signal"][-1] is not None else None,
        "ema_fast": round(ema_fast[-1], 4) if ema_fast[-1] is not None else None,
        "ema_fast_period": ema_fast_period,
        "ema20": round(ema_fast[-1], 4) if ema_fast_period == 20 and ema_fast[-1] is not None else None,
        "ema_slow": round(ema_slow[-1], 4) if ema_slow[-1] is not None else None,
        "ema_slow_period": ema_slow_period,
        "ema50": round(ema_slow[-1], 4) if ema_slow_period == 50 and ema_slow[-1] is not None else None,
        "macd_fast_period": macd_fast_period,
        "macd_slow_period": macd_slow_period,
        "macd_signal_period": macd_signal_period,
        "atr": round(atr_value[-1], 4) if atr_value[-1] is not None else None,
        "atr_period": atr_period,
        "atr14": round(atr_value[-1], 4) if atr_period == 14 and atr_value[-1] is not None else None,
    }

    supports = trend.get("price_zones", {}).get("supports", [])
    resistances = trend.get("price_zones", {}).get("resistances", [])
    support = supports[0]["price"] if supports else None
    resistance = resistances[0]["price"] if resistances else trend.get("breakout", {}).get("prior_range_high")
    breakout_state = trend.get("breakout", {}).get("state", "unknown")
    trend_state = trend.get("trend", {}).get("classification", "unknown")
    flow_state = flow.get("classification", "unknown")

    bullish_evidence = []
    bearish_evidence = []
    if trend_state == "uptrend":
        bullish_evidence.append(f"EMA{ema_fast_period}/EMA{ema_slow_period} và vị trí giá đang nghiêng về xu hướng tăng")
    elif trend_state == "downtrend":
        bearish_evidence.append(f"EMA{ema_fast_period}/EMA{ema_slow_period} và vị trí giá đang nghiêng về xu hướng giảm")
    if breakout_state == "confirmed_bullish":
        bullish_evidence.append(
            f"Breakout vượt biên {trend.get('breakout', {}).get('range_lookback_bars', 20)} nến "
            "có xác nhận volume"
        )
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
        "analysis_rules_version": rule_version,
        "analysis_rule_config_sha256": rule_config_sha256,
        "analysis_rule_parameters": rule_config,
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
