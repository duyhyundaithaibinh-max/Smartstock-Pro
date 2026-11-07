from math import isfinite


def _valid(values):
    if not values or any(not isfinite(float(v)) for v in values):
        raise ValueError("A non-empty series of finite numbers is required")
    return [float(v) for v in values]


def sma(values, period):
    values = _valid(values)
    if period < 1:
        raise ValueError("period must be positive")
    return [None if i + 1 < period else sum(values[i + 1 - period:i + 1]) / period
            for i in range(len(values))]


def ema(values, period):
    values = _valid(values)
    if period < 1:
        raise ValueError("period must be positive")
    result = [None] * len(values)
    if len(values) < period:
        return result
    seed = sum(values[:period]) / period
    result[period - 1] = seed
    alpha = 2 / (period + 1)
    previous = seed
    for i in range(period, len(values)):
        previous = values[i] * alpha + previous * (1 - alpha)
        result[i] = previous
    return result


def rsi(values, period=14):
    values = _valid(values)
    result = [None] * len(values)
    if period < 1 or len(values) <= period:
        return result
    gains = [max(values[i] - values[i - 1], 0.0) for i in range(1, len(values))]
    losses = [max(values[i - 1] - values[i], 0.0) for i in range(1, len(values))]
    avg_gain = sum(gains[:period]) / period
    avg_loss = sum(losses[:period]) / period

    def score(gain, loss):
        if loss == 0:
            return 100.0 if gain > 0 else 50.0
        rs = gain / loss
        return 100 - 100 / (1 + rs)

    result[period] = score(avg_gain, avg_loss)
    for i in range(period + 1, len(values)):
        j = i - 1
        avg_gain = (avg_gain * (period - 1) + gains[j]) / period
        avg_loss = (avg_loss * (period - 1) + losses[j]) / period
        result[i] = score(avg_gain, avg_loss)
    return result


def macd(values, fast=12, slow=26, signal=9):
    values = _valid(values)
    if fast >= slow:
        raise ValueError("fast period must be smaller than slow period")
    fast_ema, slow_ema = ema(values, fast), ema(values, slow)
    line = [None if a is None or b is None else a - b for a, b in zip(fast_ema, slow_ema)]
    valid_start = next((i for i, v in enumerate(line) if v is not None), len(line))
    compact = [v for v in line[valid_start:] if v is not None]
    signal_compact = ema(compact, signal) if compact else []
    signal_line = [None] * len(values)
    for offset, value in enumerate(signal_compact):
        signal_line[valid_start + offset] = value
    histogram = [None if a is None or b is None else a - b for a, b in zip(line, signal_line)]
    return {"macd": line, "signal": signal_line, "histogram": histogram}


def atr(highs, lows, closes, period=14):
    highs, lows, closes = _valid(highs), _valid(lows), _valid(closes)
    if not (len(highs) == len(lows) == len(closes)):
        raise ValueError("OHLC arrays must have equal length")
    true_ranges = []
    for i, (high, low) in enumerate(zip(highs, lows)):
        if low > high:
            raise ValueError("low cannot exceed high")
        true_ranges.append(high - low if i == 0 else max(
            high - low, abs(high - closes[i - 1]), abs(low - closes[i - 1])))
    return ema(true_ranges, period)


def obv(closes, volumes):
    closes, volumes = _valid(closes), _valid(volumes)
    if len(closes) != len(volumes):
        raise ValueError("close and volume arrays must have equal length")
    result, current = [], 0.0
    for i, volume in enumerate(volumes):
        if i:
            current += volume if closes[i] > closes[i - 1] else -volume if closes[i] < closes[i - 1] else 0
        result.append(current)
    return result
