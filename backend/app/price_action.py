"""Deterministic trend and price-zone analysis from sourced OHLCV candles.

This module intentionally produces rule-based observations, not trading advice.
"""
from math import isfinite

from .indicators import atr, ema


def _validate_series(highs, lows, closes, volumes):
    arrays = [list(map(float, values)) for values in (highs, lows, closes, volumes)]
    if len({len(values) for values in arrays}) != 1:
        raise ValueError("OHLCV arrays must have equal length")
    if not arrays[0]:
        raise ValueError("At least one OHLCV candle is required")
    highs, lows, closes, volumes = arrays
    if any(not isfinite(value) for values in arrays for value in values):
        raise ValueError("OHLCV values must be finite")
    if any(value < 0 for values in (highs, lows, closes, volumes) for value in values):
        raise ValueError("OHLCV values cannot be negative")
    for index, (high, low, close) in enumerate(zip(highs, lows, closes)):
        if high < low or close < low or close > high:
            raise ValueError(f"Invalid OHLC relationship at index {index}")
    return highs, lows, closes, volumes


def _pivot_levels(values, is_high, lookback=120, wing=2):
    start = max(wing, len(values) - lookback)
    end = len(values) - wing
    pivots = []
    for index in range(start, end):
        window = values[index - wing:index + wing + 1]
        value = values[index]
        if (value == max(window) if is_high else value == min(window)):
            pivots.append((index, value))
    return pivots


def _cluster_levels(pivots, tolerance, total_bars):
    clusters = []
    for index, value in sorted(pivots, key=lambda item: item[1]):
        match = next((cluster for cluster in clusters
                      if abs(value - cluster["mean"]) <= tolerance), None)
        if match is None:
            clusters.append({"values": [value], "last_index": index})
        else:
            match["values"].append(value)
            match["last_index"] = max(match["last_index"], index)
            match["mean"] = sum(match["values"]) / len(match["values"])
        if clusters and "mean" not in clusters[-1]:
            clusters[-1]["mean"] = sum(clusters[-1]["values"]) / len(clusters[-1]["values"])
    return [
        {
            "price": round(sum(cluster["values"]) / len(cluster["values"]), 4),
            "touches": len(cluster["values"]),
            "last_seen_bars_ago": max(0, total_bars - 1 - cluster["last_index"]),
        }
        for cluster in clusters
    ]


def _nearest_levels(levels, close, side, limit=3):
    if side == "support":
        selected = [level for level in levels if level["price"] <= close]
        return sorted(selected, key=lambda item: close - item["price"])[:limit]
    selected = [level for level in levels if level["price"] >= close]
    return sorted(selected, key=lambda item: item["price"] - close)[:limit]


def analyze_price_action(
    highs, lows, closes, volumes, timestamps=None,
    lookback=120, wing=2, range_lookback=20,
    volume_confirmation_pct=120, breakout_buffer_atr_pct=20,
):
    highs, lows, closes, volumes = _validate_series(highs, lows, closes, volumes)
    count = len(closes)
    if not isinstance(lookback, int) or not 20 <= lookback <= 5000:
        raise ValueError("lookback must be an integer from 20 to 5000")
    if not isinstance(wing, int) or not 1 <= wing <= 10:
        raise ValueError("wing must be an integer from 1 to 10")
    if not isinstance(range_lookback, int) or not 20 <= range_lookback <= 250:
        raise ValueError("range_lookback must be an integer from 20 to 250")
    if not isinstance(volume_confirmation_pct, int) or not 100 <= volume_confirmation_pct <= 500:
        raise ValueError("volume_confirmation_pct must be an integer from 100 to 500")
    if not isinstance(breakout_buffer_atr_pct, int) or not 0 <= breakout_buffer_atr_pct <= 200:
        raise ValueError("breakout_buffer_atr_pct must be an integer from 0 to 200")
    if timestamps is not None and len(timestamps) != count:
        raise ValueError("timestamps and OHLCV arrays must have equal length")

    if count < 20:
        return {
            "status": "insufficient_data",
            "bars_available": count,
            "bars_required": 20,
            "message": "Cần tối thiểu 20 nến để xác định vùng giá sơ bộ.",
        }

    close = closes[-1]
    atr_values = atr(highs, lows, closes, 14)
    current_atr = atr_values[-1]
    if current_atr is None or current_atr <= 0:
        current_atr = max(close * 0.01, 1e-8)

    high_pivots = _pivot_levels(highs, is_high=True, lookback=lookback, wing=wing)
    low_pivots = _pivot_levels(lows, is_high=False, lookback=lookback, wing=wing)
    tolerance = max(current_atr * 0.5, close * 0.003)
    high_levels = _cluster_levels(high_pivots, tolerance, count)
    low_levels = _cluster_levels(low_pivots, tolerance, count)

    supports = _nearest_levels(low_levels, close, "support")
    resistances = _nearest_levels(high_levels, close, "resistance")

    # The prior 20-bar range excludes the current candle to avoid look-ahead.
    prior_count = min(range_lookback, count - 1)
    prior_high = max(highs[-(prior_count + 1):-1])
    prior_low = min(lows[-(prior_count + 1):-1])
    prior_volumes = volumes[-(prior_count + 1):-1]
    average_volume = sum(prior_volumes) / len(prior_volumes)
    volume_ratio = volumes[-1] / average_volume if average_volume > 0 else None
    breakout_buffer = current_atr * (breakout_buffer_atr_pct / 100)
    breakdown_buffer = current_atr * (breakout_buffer_atr_pct / 100)

    bullish_breakout = close > prior_high + breakout_buffer
    bearish_breakdown = close < prior_low - breakdown_buffer
    volume_threshold = volume_confirmation_pct / 100
    volume_confirmed = volume_ratio is not None and volume_ratio >= volume_threshold

    if bullish_breakout and volume_confirmed:
        breakout_state = "confirmed_bullish"
    elif bullish_breakout:
        breakout_state = "unconfirmed_bullish"
    elif bearish_breakdown and volume_confirmed:
        breakout_state = "confirmed_bearish"
    elif bearish_breakdown:
        breakout_state = "unconfirmed_bearish"
    elif close >= prior_high - breakout_buffer:
        breakout_state = "testing_resistance"
    elif close <= prior_low + breakdown_buffer:
        breakout_state = "testing_support"
    else:
        breakout_state = "inside_range"

    ema20 = ema(closes, 20)
    ema50 = ema(closes, 50)
    trend = "sideways"
    trend_reasons = []
    if ema50[-1] is not None:
        slope20 = ema20[-1] - ema20[-6] if len(ema20) >= 6 and ema20[-6] is not None else 0.0
        if ema20[-1] > ema50[-1] and close > ema20[-1] and slope20 > current_atr * 0.05:
            trend = "uptrend"
            trend_reasons = ["EMA20 nằm trên EMA50", "Giá đóng cửa trên EMA20", "EMA20 có độ dốc dương"]
        elif ema20[-1] < ema50[-1] and close < ema20[-1] and slope20 < -current_atr * 0.05:
            trend = "downtrend"
            trend_reasons = ["EMA20 nằm dưới EMA50", "Giá đóng cửa dưới EMA20", "EMA20 có độ dốc âm"]
        else:
            trend_reasons = ["Các điều kiện EMA và vị trí giá chưa đồng thuận"]
    else:
        trend_reasons = ["Chưa đủ 50 nến để đánh giá xu hướng bằng EMA20/EMA50"]

    resistance_level = round(prior_high, 4)
    support_level = round(prior_low, 4)
    if breakout_state == "confirmed_bullish":
        confirmation = f"Đóng cửa cao hơn {resistance_level} ít nhất 0,2 ATR và volume >= {volume_threshold:.2f} lần trung bình {prior_count} nến."
        invalidation = f"Đóng cửa quay xuống dưới vùng breakout {resistance_level}; cần đánh giá lại breakout."
    elif breakout_state == "confirmed_bearish":
        confirmation = f"Đóng cửa thấp hơn {support_level} ít nhất 0,2 ATR và volume >= {volume_threshold:.2f} lần trung bình {prior_count} nến."
        invalidation = f"Đóng cửa quay lên trên vùng breakdown {support_level}; cần đánh giá lại breakdown."
    else:
        confirmation = f"Chờ đóng cửa vượt {resistance_level} hoặc thủng {support_level} với biên tối thiểu 0,2 ATR và volume >= {volume_threshold:.2f} lần trung bình {prior_count} nến."
        invalidation = "Chưa có tín hiệu breakout/breakdown được xác nhận; không diễn giải việc chạm vùng giá là phá vỡ."

    return {
        "status": "ok",
        "bars_available": count,
        "as_of": timestamps[-1] if timestamps else None,
        "trend": {
            "classification": trend,
            "ema20": round(ema20[-1], 4) if ema20[-1] is not None else None,
            "ema50": round(ema50[-1], 4) if ema50[-1] is not None else None,
            "reasons": trend_reasons,
            "method": "EMA20/EMA50 alignment, close location and 5-bar EMA20 slope normalized by ATR14",
        },
        "price_zones": {
            "supports": supports,
            "resistances": resistances,
            "lookback_bars": min(lookback, count),
            "pivot_wing": wing,
            "cluster_tolerance": round(tolerance, 4),
            "note": "Các vùng được suy ra từ pivot OHLC; không phải vùng cung cầu cấp lệnh hoặc dữ liệu order book.",
        },
        "breakout": {
            "state": breakout_state,
            "prior_range_high": resistance_level,
            "prior_range_low": support_level,
            "range_lookback_bars": prior_count,
            "close": round(close, 4),
            "atr14": round(current_atr, 4),
            "volume": volumes[-1],
            "average_prior_volume": round(average_volume, 4),
            "volume_ratio": round(volume_ratio, 4) if volume_ratio is not None else None,
            "volume_confirmation_threshold": volume_threshold,
            "price_buffer_atr": breakout_buffer_atr_pct / 100,
            "confirmation_condition": confirmation,
            "invalidation_condition": invalidation,
        },
        "limitations": [
            "Kết quả là phép tính xác định từ OHLCV được cung cấp, không phải khuyến nghị mua bán.",
            "Chưa tự điều chỉnh giá cho cổ tức, thưởng cổ phiếu hoặc quyền mua.",
            "Pivot cần các nến xác nhận phía sau nên vùng giá có độ trễ.",
            "Volume chỉ xác nhận tương đối so với 20 nến trước; không đại diện dòng tiền tổ chức.",
        ],
    }
