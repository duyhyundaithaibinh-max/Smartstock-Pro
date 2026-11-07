"""Deterministic Fibonacci price and time projections from confirmed OHLCV pivots.

All indices are zero-based within the requested candle window. Future time
projections are expressed as trading-bar offsets only; no calendar dates are
invented because an exchange trading calendar is not part of this engine.
"""
from math import isfinite

from .price_action import _pivot_levels

RETRACEMENT_RATIOS = (0.236, 0.382, 0.5, 0.618, 0.786)
EXTENSION_RATIOS = (1.0, 1.272, 1.618, 2.0)
TIME_RATIOS = (0.382, 0.5, 0.618, 1.0, 1.272, 1.618, 2.0)


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


def _confirmed_swings(highs, lows, lookback, wing):
    start = max(wing, len(highs) - lookback)
    high_pivots = _pivot_levels(highs, True, lookback=lookback, wing=wing)
    low_pivots = _pivot_levels(lows, False, lookback=lookback, wing=wing)
    events = [(index, "high", price) for index, price in high_pivots if index >= start]
    events += [(index, "low", price) for index, price in low_pivots if index >= start]
    events.sort(key=lambda item: (item[0], item[1]))

    # Collapse consecutive pivots of the same type, retaining the more extreme.
    alternating = []
    for event in events:
        if alternating and alternating[-1][1] == event[1]:
            previous = alternating[-1]
            more_extreme = event[2] > previous[2] if event[1] == "high" else event[2] < previous[2]
            if more_extreme:
                alternating[-1] = event
        else:
            alternating.append(event)
    return alternating


def analyze_fibonacci(highs, lows, closes, timestamps=None, lookback=250, wing=2):
    highs, lows, closes = _validate(highs, lows, closes, timestamps)
    count = len(closes)
    if lookback < 10:
        raise ValueError("lookback must be at least 10")
    if wing < 1:
        raise ValueError("wing must be at least 1")
    if count < (2 * wing + 3):
        return {
            "status": "insufficient_data",
            "bars_available": count,
            "bars_required": 2 * wing + 3,
        }

    pivots = _confirmed_swings(highs, lows, lookback, wing)
    if len(pivots) < 2:
        return {
            "status": "no_confirmed_swing",
            "bars_available": count,
            "pivot_count": len(pivots),
            "message": "Chưa có đủ hai pivot trái dấu đã được nến sau xác nhận.",
        }

    start_pivot, end_pivot = pivots[-2], pivots[-1]
    start_index, start_type, start_price = start_pivot
    end_index, end_type, end_price = end_pivot
    if end_index <= start_index or start_price == end_price:
        return {"status": "no_confirmed_swing", "bars_available": count, "pivot_count": len(pivots)}

    direction = "bullish" if start_type == "low" and end_type == "high" else "bearish"
    swing_size = abs(end_price - start_price)
    if direction == "bullish":
        retracements = [
            {"ratio": ratio, "price": round(end_price - swing_size * ratio, 4)}
            for ratio in RETRACEMENT_RATIOS
        ]
        extensions = [
            {"ratio": ratio, "price": round(start_price + swing_size * ratio, 4)}
            for ratio in EXTENSION_RATIOS
        ]
    else:
        retracements = [
            {"ratio": ratio, "price": round(end_price + swing_size * ratio, 4)}
            for ratio in RETRACEMENT_RATIOS
        ]
        extensions = [
            {"ratio": ratio, "price": round(start_price - swing_size * ratio, 4)}
            for ratio in EXTENSION_RATIOS
        ]

    duration = end_index - start_index
    time_projections = []
    for ratio in TIME_RATIOS:
        projected_index = end_index + round(duration * ratio)
        bars_from_latest = projected_index - (count - 1)
        time_projections.append({
            "ratio": ratio,
            "projected_bar_index": projected_index,
            "bars_from_latest": bars_from_latest,
            "position": "future" if bars_from_latest > 0 else ("current" if bars_from_latest == 0 else "past"),
        })

    return {
        "status": "ok",
        "bars_available": count,
        "as_of": timestamps[-1] if timestamps else None,
        "direction": direction,
        "swing": {
            "start": {
                "index": start_index,
                "type": start_type,
                "price": round(start_price, 4),
                "timestamp": timestamps[start_index] if timestamps else None,
            },
            "end": {
                "index": end_index,
                "type": end_type,
                "price": round(end_price, 4),
                "timestamp": timestamps[end_index] if timestamps else None,
            },
            "size": round(swing_size, 4),
            "duration_bars": duration,
        },
        "price": {
            "retracements": retracements,
            "extensions": extensions,
            "note": "Các mức được tính từ hai pivot gần nhất trái dấu đã xác nhận; là mốc tham chiếu, không phải dự báo chắc chắn.",
        },
        "time": {
            "unit": "trading_bars",
            "anchor_index": end_index,
            "projections": time_projections,
            "note": "Dự phóng theo số nến giao dịch; không quy đổi sang ngày lịch khi chưa có lịch giao dịch sàn.",
        },
        "method": {
            "pivot_wing": wing,
            "lookback_bars": min(lookback, count),
            "pivot_confirmation": f"Mỗi pivot cần {wing} nến bên phải để xác nhận.",
            "selection": "Hai pivot trái dấu gần nhất trong cửa sổ; pivot cùng loại liên tiếp được gộp theo cực trị.",
        },
        "limitations": [
            "Kết quả phụ thuộc cửa sổ dữ liệu, pivot_wing và swing được chọn.",
            "Fibonacci là phép chiếu tỷ lệ, không xác nhận xác suất đảo chiều hoặc mục tiêu giá.",
            "Chưa tự điều chỉnh dữ liệu cho cổ tức, thưởng cổ phiếu hoặc quyền mua.",
            "Time projection là số nến giao dịch, không phải ngày lịch hay thời điểm chắc chắn xảy ra biến động.",
        ],
    }
