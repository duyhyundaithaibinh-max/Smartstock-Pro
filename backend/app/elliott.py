"""Rule-based Elliott impulse-wave hypotheses from confirmed OHLCV pivots.

This module deliberately reports structural candidates, not a definitive wave count.
"""
from math import isfinite

from .price_action import _pivot_levels


def _validate(highs, lows, closes, timestamps=None):
    arrays = [list(map(float, values)) for values in (highs, lows, closes)]
    if len({len(values) for values in arrays}) != 1:
        raise ValueError("High, low and close arrays must have equal length")
    if not arrays[0]:
        raise ValueError("At least one candle is required")
    if any(not isfinite(value) or value < 0 for values in arrays for value in values):
        raise ValueError("OHLC values must be finite and nonnegative")
    for index, (high, low, close) in enumerate(zip(*arrays)):
        if high < low or close < low or close > high:
            raise ValueError(f"Invalid OHLC relationship at index {index}")
    if timestamps is not None and len(timestamps) != len(arrays[0]):
        raise ValueError("timestamps and OHLC arrays must have equal length")
    return arrays


def _alternating_pivots(highs, lows, lookback=250, wing=2):
    high_pivots = _pivot_levels(highs, True, lookback=lookback, wing=wing)
    low_pivots = _pivot_levels(lows, False, lookback=lookback, wing=wing)
    events = [(i, "high", p) for i, p in high_pivots]
    events += [(i, "low", p) for i, p in low_pivots]
    events.sort(key=lambda item: (item[0], item[1]))
    result = []
    for event in events:
        if result and result[-1][1] == event[1]:
            previous = result[-1]
            extreme = event[2] > previous[2] if event[1] == "high" else event[2] < previous[2]
            if extreme:
                result[-1] = event
        else:
            result.append(event)
    return result


def _evaluate_impulse(pivots):
    if len(pivots) != 6:
        raise ValueError("Exactly six alternating pivots are required")
    points = pivots
    bullish = [p[1] for p in points] == ["low", "high", "low", "high", "low", "high"]
    bearish = [p[1] for p in points] == ["high", "low", "high", "low", "high", "low"]
    if not bullish and not bearish:
        return None

    prices = [p[2] for p in points]
    if bullish:
        wave1 = prices[1] - prices[0]
        wave2 = prices[1] - prices[2]
        wave3 = prices[3] - prices[2]
        wave4 = prices[3] - prices[4]
        wave5 = prices[5] - prices[4]
        checks = [
            ("wave_2_does_not_exceed_wave_1_origin", prices[2] > prices[0],
             "Wave 2 không được xuyên thủng điểm bắt đầu Wave 1."),
            ("wave_3_exceeds_wave_1_end", prices[3] > prices[1],
             "Wave 3 phải vượt đỉnh Wave 1."),
            ("wave_4_does_not_overlap_wave_1", prices[4] > prices[1],
             "Wave 4 không được đi vào vùng giá Wave 1 trong impulse tiêu chuẩn."),
            ("wave_3_is_not_shortest", wave3 >= min(wave1, wave5),
             "Wave 3 không được là sóng ngắn nhất trong Wave 1, 3 và 5."),
        ]
        direction = "bullish"
        confirm = f"Giá đóng cửa vượt pivot Wave 5 tại {prices[5]} để xác nhận tiếp diễn."
        invalidate = f"Giá phá xuống dưới pivot Wave 4 tại {prices[4]} làm suy yếu cách đếm."
    else:
        wave1 = prices[0] - prices[1]
        wave2 = prices[2] - prices[1]
        wave3 = prices[2] - prices[3]
        wave4 = prices[4] - prices[3]
        wave5 = prices[4] - prices[5]
        checks = [
            ("wave_2_does_not_exceed_wave_1_origin", prices[2] < prices[0],
             "Wave 2 không được vượt điểm bắt đầu Wave 1."),
            ("wave_3_exceeds_wave_1_end", prices[3] < prices[1],
             "Wave 3 phải phá đáy Wave 1."),
            ("wave_4_does_not_overlap_wave_1", prices[4] < prices[1],
             "Wave 4 không được đi vào vùng giá Wave 1 trong impulse tiêu chuẩn."),
            ("wave_3_is_not_shortest", wave3 >= min(wave1, wave5),
             "Wave 3 không được là sóng ngắn nhất trong Wave 1, 3 và 5."),
        ]
        direction = "bearish"
        confirm = f"Giá đóng cửa thủng pivot Wave 5 tại {prices[5]} để xác nhận tiếp diễn."
        invalidate = f"Giá vượt pivot Wave 4 tại {prices[4]} làm suy yếu cách đếm."

    passed = sum(1 for _, ok, _ in checks if ok)
    return {
        "type": "five_wave_impulse",
        "direction": direction,
        "status": "structurally_valid_candidate" if passed == len(checks) else "invalidated_candidate",
        "rule_score": round(passed / len(checks) * 100),
        "rule_checks": [
            {"rule": name, "passed": bool(ok), "explanation": explanation}
            for name, ok, explanation in checks
        ],
        "waves": [
            {"wave": f"Wave {index + 1}", "from_price": round(prices[index], 4),
             "to_price": round(prices[index + 1], 4),
             "length": round(abs(prices[index + 1] - prices[index]), 4)}
            for index in range(5)
        ],
        "confirmation_condition": confirm,
        "invalidation_condition": invalidate,
        "note": "Điểm số phản ánh số quy tắc cấu trúc đạt được, không phải xác suất thành công.",
    }


def analyze_elliott(highs, lows, closes, timestamps=None, lookback=250, wing=2):
    highs, lows, closes = _validate(highs, lows, closes, timestamps)
    count = len(closes)
    if lookback < 10:
        raise ValueError("lookback must be at least 10")
    if wing < 1:
        raise ValueError("wing must be at least 1")
    pivots = _alternating_pivots(highs, lows, lookback=lookback, wing=wing)
    if len(pivots) < 6:
        return {
            "status": "incomplete",
            "bars_available": count,
            "confirmed_pivots": [
                {"index": i, "type": kind, "price": round(price, 4),
                 "timestamp": timestamps[i] if timestamps else None}
                for i, kind, price in pivots
            ],
            "required_pivots": 6,
            "message": "Chưa đủ sáu pivot luân phiên đã xác nhận để đánh giá một impulse 5 sóng.",
        }

    selected = pivots[-6:]
    candidate = _evaluate_impulse(selected)
    if candidate is None:
        return {
            "status": "no_impulse_candidate",
            "bars_available": count,
            "confirmed_pivots": [
                {"index": i, "type": kind, "price": round(price, 4)}
                for i, kind, price in selected
            ],
            "message": "Sáu pivot gần nhất không tạo thành chuỗi luân phiên phù hợp với impulse tăng hoặc giảm.",
        }

    candidate["pivots"] = [
        {"label": f"P{index}", "index": i, "type": kind, "price": round(price, 4),
         "timestamp": timestamps[i] if timestamps else None}
        for index, (i, kind, price) in enumerate(selected)
    ]
    return {
        "status": candidate["status"],
        "bars_available": count,
        "as_of": timestamps[-1] if timestamps else None,
        "candidate": candidate,
        "method": {
            "pivot_wing": wing,
            "lookback_bars": min(lookback, count),
            "selection": "Sáu pivot luân phiên gần nhất đã được wing nến bên phải xác nhận.",
            "scope": "Impulse 5 sóng tiêu chuẩn; chưa nhận diện leading/ending diagonal hoặc toàn bộ mẫu điều chỉnh ABC/complex.",
        },
        "limitations": [
            "Elliott có nhiều cách đếm; kết quả chỉ là giả thuyết cấu trúc theo bộ quy tắc giới hạn.",
            "Rule score không phải xác suất dự báo và không được dùng độc lập làm tín hiệu giao dịch.",
            "Pivot cần nến xác nhận phía sau nên có độ trễ; cửa sổ và wing có thể làm thay đổi cách đếm.",
            "Chưa tự điều chỉnh giá cho cổ tức, thưởng cổ phiếu hoặc quyền mua.",
        ],
    }
