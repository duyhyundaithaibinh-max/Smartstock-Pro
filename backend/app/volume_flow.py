"""Deterministic volume-flow and accumulation/distribution observations from OHLCV."""
from math import isfinite


def _validate(highs, lows, closes, volumes):
    arrays = [list(map(float, values)) for values in (highs, lows, closes, volumes)]
    if len({len(values) for values in arrays}) != 1:
        raise ValueError("OHLCV arrays must have equal length")
    if not arrays[0]:
        raise ValueError("At least one OHLCV candle is required")
    if any(not isfinite(value) or value < 0 for values in arrays for value in values):
        raise ValueError("OHLCV values must be finite and nonnegative")
    for index, (high, low, close) in enumerate(zip(*arrays[:3])):
        if high < low or close < low or close > high:
            raise ValueError(f"Invalid OHLC relationship at index {index}")
    return arrays


def _obv(closes, volumes):
    result = [0.0]
    for index in range(1, len(closes)):
        if closes[index] > closes[index - 1]:
            result.append(result[-1] + volumes[index])
        elif closes[index] < closes[index - 1]:
            result.append(result[-1] - volumes[index])
        else:
            result.append(result[-1])
    return result


def analyze_volume_flow(highs, lows, closes, volumes, timestamps=None, window=20):
    highs, lows, closes, volumes = _validate(highs, lows, closes, volumes)
    count = len(closes)
    if timestamps is not None and len(timestamps) != count:
        raise ValueError("timestamps and OHLCV arrays must have equal length")
    if window < 2:
        raise ValueError("window must be at least 2")
    if count < window:
        return {
            "status": "insufficient_data",
            "bars_available": count,
            "bars_required": window,
        }

    multipliers = []
    money_flow_volumes = []
    for high, low, close, volume in zip(highs, lows, closes, volumes):
        spread = high - low
        multiplier = ((close - low) - (high - close)) / spread if spread > 0 else 0.0
        multipliers.append(multiplier)
        money_flow_volumes.append(multiplier * volume)

    adl = []
    running = 0.0
    for value in money_flow_volumes:
        running += value
        adl.append(running)

    total_volume = sum(volumes[-window:])
    cmf = sum(money_flow_volumes[-window:]) / total_volume if total_volume > 0 else None
    obv = _obv(closes, volumes)
    obv_change = obv[-1] - obv[-window]
    price_change_pct = ((closes[-1] / closes[-window]) - 1) * 100 if closes[-window] > 0 else None

    up_volume = 0.0
    down_volume = 0.0
    for index in range(count - window + 1, count):
        if closes[index] > closes[index - 1]:
            up_volume += volumes[index]
        elif closes[index] < closes[index - 1]:
            down_volume += volumes[index]
    up_down_ratio = up_volume / down_volume if down_volume > 0 else (None if up_volume == 0 else "infinite")

    recent_volume = sum(volumes[-10:]) / min(10, count)
    prior_slice = volumes[-30:-10] if count >= 30 else volumes[:-10]
    prior_volume = sum(prior_slice) / len(prior_slice) if prior_slice else None
    volume_contraction = (
        prior_volume is not None and prior_volume > 0 and recent_volume < prior_volume * 0.8
    )

    divergence = "none"
    if price_change_pct is not None:
        if price_change_pct > 0 and obv_change < 0:
            divergence = "bearish_price_volume_divergence"
        elif price_change_pct < 0 and obv_change > 0:
            divergence = "bullish_price_volume_divergence"

    if cmf is not None and cmf >= 0.05 and obv_change > 0:
        classification = "accumulation_candidate"
    elif cmf is not None and cmf <= -0.05 and obv_change < 0:
        classification = "distribution_candidate"
    else:
        classification = "mixed_or_neutral"

    return {
        "status": "ok",
        "bars_available": count,
        "as_of": timestamps[-1] if timestamps else None,
        "window": window,
        "money_flow": {
            "chaikin_money_flow": round(cmf, 6) if cmf is not None else None,
            "adl_latest": round(adl[-1], 4),
            "adl_change_window": round(adl[-1] - adl[-window], 4),
            "obv_latest": round(obv[-1], 4),
            "obv_change_window": round(obv_change, 4),
            "up_volume": round(up_volume, 4),
            "down_volume": round(down_volume, 4),
            "up_down_volume_ratio": round(up_down_ratio, 4) if isinstance(up_down_ratio, float) else up_down_ratio,
            "price_change_pct": round(price_change_pct, 4) if price_change_pct is not None else None,
            "price_volume_divergence": divergence,
        },
        "volume_behavior": {
            "recent_10_bar_average": round(recent_volume, 4),
            "prior_comparison_average": round(prior_volume, 4) if prior_volume is not None else None,
            "contraction": volume_contraction,
            "contraction_threshold": "recent 10-bar average < 80% of preceding comparison average",
        },
        "classification": classification,
        "evidence": [
            f"CMF({window}) = {round(cmf, 6) if cmf is not None else 'unavailable'}",
            f"OBV change over window = {round(obv_change, 4)}",
            f"Price change over window = {round(price_change_pct, 4) if price_change_pct is not None else 'unavailable'}%",
            f"Price/volume divergence = {divergence}",
            f"Volume contraction = {volume_contraction}",
        ],
        "limitations": [
            "Chỉ sử dụng OHLCV; không có dữ liệu khớp lệnh, chủ động mua/bán, giao dịch nhà đầu tư hoặc order book.",
            "CMF và ADL phụ thuộc vị trí giá đóng cửa trong biên độ nến; không đại diện trực tiếp dòng tiền tổ chức.",
            "OBV và up/down volume là phép đo khối lượng theo biến động giá, không xác định danh tính bên mua/bên bán.",
            "Nhãn accumulation/distribution chỉ là ứng viên theo ngưỡng CMF và OBV, không phải kết luận chắc chắn.",
        ],
    }
