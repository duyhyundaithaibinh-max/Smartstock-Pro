from math import isfinite

def _valid(values):
    if not values or any(not isfinite(float(v)) for v in values):
        raise ValueError("A non-empty series of finite numbers is required")
    return [float(v) for v in values]

def sma(values, period):
    values = _valid(values)
    if period < 1: raise ValueError("period must be positive")
    return [None if i + 1 < period else sum(values[i + 1 - period:i + 1]) / period for i in range(len(values))]

def ema(values, period):
    values = _valid(values)
    if period < 1: raise ValueError("period must be positive")
    result = [None] * len(values)
    if len(values) < period: return result
    previous = sum(values[:period]) / period
    result[period - 1] = previous
    alpha = 2 / (period + 1)
    for i in range(period, len(values)):
        previous = values[i] * alpha + previous * (1 - alpha)
        result[i] = previous
    return result

def rsi(values, period=14):
    values = _valid(values); result = [None] * len(values)
    if period < 1 or len(values) <= period: return result
    gains = [max(values[i] - values[i-1], 0.0) for i in range(1, len(values))]
    losses = [max(values[i-1] - values[i], 0.0) for i in range(1, len(values))]
    avg_gain, avg_loss = sum(gains[:period])/period, sum(losses[:period])/period
    def score(gain, loss):
        if loss == 0: return 100.0 if gain > 0 else 50.0
        return 100 - 100/(1 + gain/loss)
    result[period] = score(avg_gain, avg_loss)
    for i in range(period + 1, len(values)):
        j = i - 1
        avg_gain = (avg_gain*(period-1) + gains[j])/period
        avg_loss = (avg_loss*(period-1) + losses[j])/period
        result[i] = score(avg_gain, avg_loss)
    return result

def macd(values, fast=12, slow=26, signal=9):
    values = _valid(values)
    if fast >= slow: raise ValueError("fast period must be smaller than slow period")
    a, b = ema(values, fast), ema(values, slow)
    line = [None if x is None or y is None else x-y for x,y in zip(a,b)]
    start = next((i for i,v in enumerate(line) if v is not None), len(line))
    compact = [v for v in line[start:] if v is not None]
    sig = ema(compact, signal) if compact else []
    signal_line = [None]*len(values)
    for offset, value in enumerate(sig): signal_line[start+offset] = value
    hist = [None if x is None or y is None else x-y for x,y in zip(line,signal_line)]
    return {"macd":line,"signal":signal_line,"histogram":hist}

def atr(highs, lows, closes, period=14):
    highs,lows,closes = map(_valid,(highs,lows,closes))
    if not (len(highs)==len(lows)==len(closes)) or period<1: raise ValueError("Invalid OHLC arrays or period")
    tr=[]
    for i,(h,l) in enumerate(zip(highs,lows)):
        if l>h: raise ValueError("low cannot exceed high")
        tr.append(h-l if i==0 else max(h-l,abs(h-closes[i-1]),abs(l-closes[i-1])))
    result=[None]*len(tr)
    if len(tr)<period: return result
    previous=sum(tr[:period])/period; result[period-1]=previous
    for i in range(period,len(tr)):
        previous=(previous*(period-1)+tr[i])/period; result[i]=previous
    return result

def obv(closes, volumes):
    closes,volumes=map(_valid,(closes,volumes))
    if len(closes)!=len(volumes): raise ValueError("close and volume arrays must have equal length")
    result=[]; current=0.0
    for i,volume in enumerate(volumes):
        if i: current += volume if closes[i]>closes[i-1] else -volume if closes[i]<closes[i-1] else 0
        result.append(current)
    return result

def bollinger(values, period=20, deviations=2.0):
    values=_valid(values); middle=sma(values,period); upper=[]; lower=[]
    for i,mean in enumerate(middle):
        if mean is None: upper.append(None); lower.append(None); continue
        window=values[i+1-period:i+1]
        width=deviations*(sum((v-mean)**2 for v in window)/period)**0.5
        upper.append(mean+width); lower.append(mean-width)
    return {"middle":middle,"upper":upper,"lower":lower}

def vwap(highs,lows,closes,volumes):
    highs,lows,closes,volumes=map(_valid,(highs,lows,closes,volumes))
    if len({len(highs),len(lows),len(closes),len(volumes)})!=1: raise ValueError("OHLCV arrays must have equal length")
    pv=volume_sum=0.0; result=[]
    for h,l,c,v in zip(highs,lows,closes,volumes):
        pv += ((h+l+c)/3)*v; volume_sum += v
        result.append(pv/volume_sum if volume_sum else None)
    return result

def stochastic(highs,lows,closes,period=14,smooth=3):
    highs,lows,closes=map(_valid,(highs,lows,closes))
    if len({len(highs),len(lows),len(closes)})!=1: raise ValueError("OHLC arrays must have equal length")
    raw=[None]*len(closes)
    for i in range(period-1,len(closes)):
        hi=max(highs[i+1-period:i+1]); lo=min(lows[i+1-period:i+1])
        raw[i]=50.0 if hi==lo else 100*(closes[i]-lo)/(hi-lo)
    valid=[v for v in raw if v is not None]; smoothed=sma(valid,smooth) if valid else []
    signal=[None]*len(raw); start=next((i for i,v in enumerate(raw) if v is not None),len(raw))
    for offset,value in enumerate(smoothed): signal[start+offset]=value
    return {"k":raw,"d":signal}

def volume_profile(highs,lows,closes,volumes,bins=24,value_area=0.70):
    highs,lows,closes,volumes=map(_valid,(highs,lows,closes,volumes))
    if len({len(highs),len(lows),len(closes),len(volumes)})!=1: raise ValueError("OHLCV arrays must have equal length")
    if bins<2 or not 0<value_area<=1: raise ValueError("Invalid bins or value_area")
    minimum,maximum=min(lows),max(highs)
    if maximum==minimum:
        return {"poc":minimum,"value_area_low":minimum,"value_area_high":maximum,"total_volume":sum(volumes),"bins":[{"price":minimum,"volume":sum(volumes)}]}
    width=(maximum-minimum)/bins; hist=[0.0]*bins
    for h,l,c,v in zip(highs,lows,closes,volumes):
        idx=min(bins-1,max(0,int((((h+l+c)/3)-minimum)/width))); hist[idx]+=v
    poc=max(range(bins),key=lambda i:hist[i]); target=sum(hist)*value_area
    accumulated=hist[poc]; left=right=poc
    while accumulated<target and (left>0 or right<bins-1):
        lv=hist[left-1] if left>0 else -1; rv=hist[right+1] if right<bins-1 else -1
        if rv>lv: right+=1; accumulated+=hist[right]
        else: left-=1; accumulated+=hist[left]
    return {"poc":minimum+(poc+0.5)*width,"value_area_low":minimum+left*width,
            "value_area_high":minimum+(right+1)*width,"total_volume":sum(hist),
            "bins":[{"price":minimum+(i+0.5)*width,"volume":hist[i]} for i in range(bins)]}
