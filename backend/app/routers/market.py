import csv
import io
from datetime import datetime, timezone
from fastapi import APIRouter, HTTPException, Query, UploadFile, File
from pydantic import ValidationError
from ..db import connection
from ..schemas import SymbolCreate, Candle
from .. import indicators

router = APIRouter(prefix="/api/v1", tags=["market"])
EXCHANGES = [
    {"code": "HOSE", "name": "Sở Giao dịch Chứng khoán TP.HCM"},
    {"code": "HNX", "name": "Sở Giao dịch Chứng khoán Hà Nội"},
    {"code": "UPCOM", "name": "Thị trường UPCoM"},
]


@router.get("/markets")
def markets():
    return EXCHANGES


@router.post("/symbols", status_code=201)
def create_symbol(payload: SymbolCreate):
    with connection() as conn:
        try:
            conn.execute(
                "INSERT INTO symbols(symbol,name,exchange,sector) VALUES(?,?,?,?)",
                (payload.symbol, payload.name, payload.exchange, payload.sector),
            )
        except Exception as exc:
            if "UNIQUE" in str(exc):
                raise HTTPException(409, "Symbol already exists")
            raise
    return payload.model_dump()


@router.get("/symbols")
def list_symbols(exchange: str | None = None, q: str | None = Query(default=None, max_length=80)):
    sql = "SELECT symbol,name,exchange,sector FROM symbols"
    clauses = []
    params = []
    if exchange:
        if exchange not in {"HOSE", "HNX", "UPCOM"}:
            raise HTTPException(400, "Unsupported exchange")
        clauses.append("exchange=?")
        params.append(exchange)
    if q:
        clauses.append("(symbol LIKE ? OR name LIKE ?)")
        params.extend([f"%{q}%", f"%{q}%"])
    if clauses:
        sql += " WHERE " + " AND ".join(clauses)
    sql += " ORDER BY symbol"
    with connection() as conn:
        return [dict(row) for row in conn.execute(sql, params).fetchall()]


@router.get("/candles")
def get_candles(symbol: str, timeframe: str = "1d", limit: int = Query(500, ge=1, le=5000)):
    with connection() as conn:
        rows = conn.execute(
            """SELECT timestamp,open,high,low,close,volume,source FROM candles
            WHERE symbol=? AND timeframe=? ORDER BY timestamp DESC LIMIT ?""",
            (symbol.upper(), timeframe, limit),
        ).fetchall()
    return [dict(row) for row in reversed(rows)]


@router.post("/candles/import-csv")
async def import_csv(
    symbol: str,
    source: str = Query(min_length=2, max_length=100),
    file: UploadFile = File(...),
):
    if not file.filename or not file.filename.lower().endswith(".csv"):
        raise HTTPException(415, "Only CSV files are accepted")
    raw = await file.read(10_000_001)
    if len(raw) > 10_000_000:
        raise HTTPException(413, "CSV file exceeds 10 MB")

    try:
        reader = csv.DictReader(io.StringIO(raw.decode("utf-8-sig")))
        required = {"timestamp", "open", "high", "low", "close", "volume"}
        if not reader.fieldnames or not required.issubset(set(reader.fieldnames)):
            raise ValueError("CSV requires timestamp,open,high,low,close,volume columns")

        parsed = []
        seen_timestamps = set()
        for line_no, row in enumerate(reader, start=2):
            try:
                candle = Candle.model_validate({
                    "timestamp": row["timestamp"],
                    "open": row["open"],
                    "high": row["high"],
                    "low": row["low"],
                    "close": row["close"],
                    "volume": row["volume"],
                })
            except ValidationError as exc:
                raise ValueError(f"Invalid candle at line {line_no}: {exc}") from exc

            timestamp_key = candle.timestamp.isoformat()
            if timestamp_key in seen_timestamps:
                raise ValueError(f"Duplicate timestamp at line {line_no}: {timestamp_key}")
            seen_timestamps.add(timestamp_key)
            parsed.append(candle)
    except (UnicodeDecodeError, csv.Error, ValueError, KeyError) as exc:
        raise HTTPException(400, f"Invalid CSV: {exc}")

    if not parsed:
        raise HTTPException(400, "CSV contains no candle rows")

    now = datetime.now(timezone.utc).isoformat()
    normalized_symbol = symbol.upper()
    with connection() as conn:
        if not conn.execute("SELECT 1 FROM symbols WHERE symbol=?", (normalized_symbol,)).fetchone():
            raise HTTPException(404, "Create the symbol before importing candles")
        conn.executemany(
            """INSERT INTO candles(symbol,timeframe,timestamp,open,high,low,close,volume,source,fetched_at)
            VALUES(?,'1d',?,?,?,?,?,?,?,?) ON CONFLICT(symbol,timeframe,timestamp) DO UPDATE SET
            open=excluded.open,high=excluded.high,low=excluded.low,close=excluded.close,
            volume=excluded.volume,source=excluded.source,fetched_at=excluded.fetched_at""",
            [
                (normalized_symbol, c.timestamp.isoformat(), c.open, c.high, c.low, c.close, c.volume, source, now)
                for c in parsed
            ],
        )
    return {
        "symbol": normalized_symbol,
        "imported": len(parsed),
        "source": source,
        "timeframe": "1d",
        "timestamp_timezone": "Asia/Ho_Chi_Minh",
        "price_adjustment": "unknown",
        "note": "Price adjustment status is not inferred from OHLCV. Confirm corporate-action adjustment with the data provider.",
    }


@router.get("/indicators")
def get_indicators(symbol: str, timeframe: str = "1d", limit: int = Query(500, ge=30, le=5000)):
    candles = get_candles(symbol, timeframe, limit)
    if not candles:
        raise HTTPException(404, "No candle data found")
    closes = [c["close"] for c in candles]
    highs = [c["high"] for c in candles]
    lows = [c["low"] for c in candles]
    volumes = [c["volume"] for c in candles]
    macd = indicators.macd(closes)
    return {
        "symbol": symbol.upper(),
        "timeframe": timeframe,
        "timestamps": [c["timestamp"] for c in candles],
        "sma20": indicators.sma(closes, 20),
        "sma50": indicators.sma(closes, 50),
        "ema20": indicators.ema(closes, 20),
        "rsi14": indicators.rsi(closes, 14),
        "macd": macd,
        "atr14": indicators.atr(highs, lows, closes, 14),
        "obv": indicators.obv(closes, volumes),
        "bollinger20": indicators.bollinger(closes, 20, 2.0),
        "vwap_cumulative": indicators.vwap(highs, lows, closes, volumes),
        "stochastic14": indicators.stochastic(highs, lows, closes, 14, 3),
        "volume_profile": indicators.volume_profile(highs, lows, closes, volumes),
        "data_source": sorted({c["source"] for c in candles}),
        "note": "Indicators use stored source candles. Verify corporate-action adjustments and timeframe-specific VWAP interpretation.",
    }
