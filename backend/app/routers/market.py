import csv
import io
from typing import Annotated
from datetime import datetime, timezone
from fastapi import APIRouter, HTTPException, Query, UploadFile, File, Body
from pydantic import ValidationError
from ..db import connection
from ..schemas import SymbolCreate, Candle
from .. import indicators, price_action, fibonacci, elliott, volume_flow, analysis_report, watchlist, chart_data, stock_detail, knowledge_base, knowledge_retrieval, rule_registry, rule_evaluation

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
def list_symbols(exchange: str | None = None, q: Annotated[str | None, Query(max_length=80)] = None):
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
def get_candles(symbol: str, timeframe: str = "1d", limit: Annotated[int, Query(ge=1, le=5000)] = 500):
    with connection() as conn:
        rows = conn.execute(
            """SELECT timestamp,open,high,low,close,volume,source FROM candles
            WHERE symbol=? AND timeframe=? ORDER BY timestamp DESC LIMIT ?""",
            (symbol.upper(), timeframe, limit),
        ).fetchall()
    return [dict(row) for row in reversed(rows)]


@router.get("/symbols/{symbol}/detail")
def get_stock_detail(
    symbol: str,
    timeframe: Annotated[str, Query(min_length=2, max_length=8)] = "1d",
    limit: Annotated[int, Query(ge=1, le=5000)] = 500,
):
    """Return the latest sourced OHLCV snapshot, indicators and price zones."""
    normalized = symbol.upper()
    with connection() as conn:
        row = conn.execute(
            "SELECT symbol,name,exchange,sector FROM symbols WHERE symbol=?",
            (normalized,),
        ).fetchone()
    if row is None:
        raise HTTPException(404, "Unknown symbol")
    candles = get_candles(normalized, timeframe, limit)
    try:
        return stock_detail.build_stock_detail(
            normalized, dict(row), candles, timeframe=timeframe
        )
    except ValueError as exc:
        raise HTTPException(422, f"Unable to build stock detail: {exc}") from exc


@router.get("/candles/chart")
def get_chart_candles(
    symbol: str,
    period: Annotated[str, Query(pattern="^(daily|weekly|monthly)$")] = "daily",
    limit: Annotated[int, Query(ge=1, le=5000)] = 500,
):
    """Return stored daily OHLCV as daily, ISO-weekly or calendar-month bars."""
    daily = get_candles(symbol, "1d", min(limit * (5 if period == "weekly" else 23 if period == "monthly" else 1), 5000))
    if not daily:
        return {
            "symbol": symbol.upper(),
            "period": period,
            "status": "no_data",
            "candles": [],
            "data_sources": [],
            "note": "No stored daily OHLCV data; no prices or candles have been synthesized.",
        }
    aggregated = chart_data.aggregate_candles(daily, period)
    aggregated = aggregated[-limit:]
    return {
        "symbol": symbol.upper(),
        "period": period,
        "status": "ok" if aggregated else "no_data",
        "candles": aggregated,
        "data_sources": sorted({source for candle in aggregated for source in candle["sources"]}),
        "price_adjustment": "unknown",
        "note": "Weekly/monthly bars are aggregated from available daily source candles; missing sessions are not filled.",
    }


@router.post("/candles/import-csv")
async def import_csv(
    symbol: str,
    source: Annotated[str, Query(min_length=2, max_length=100)],
    file: UploadFile = File(...),
):
    if not file.filename or not file.filename.lower().endswith(".csv"):
        raise HTTPException(415, "Only CSV files are accepted")
    source = source.strip()
    if len(source) < 2:
        raise HTTPException(422, "Source must contain at least 2 non-whitespace characters")
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
def get_indicators(symbol: str, timeframe: str = "1d", limit: Annotated[int, Query(ge=30, le=5000)] = 500):
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



@router.get("/analysis/price-action")
def get_price_action_analysis(
    symbol: str,
    timeframe: str = "1d",
    limit: Annotated[int, Query(ge=1, le=5000)] = 500,
):
    """Deterministic trend, support/resistance and breakout analysis from stored OHLCV."""
    candles = get_candles(symbol, timeframe, limit)
    if not candles:
        raise HTTPException(404, "No candle data found")
    try:
        return {
            "symbol": symbol.upper(),
            "timeframe": timeframe,
            "data_source": sorted({c["source"] for c in candles}),
            "analysis": price_action.analyze_price_action(
                [c["high"] for c in candles],
                [c["low"] for c in candles],
                [c["close"] for c in candles],
                [c["volume"] for c in candles],
                timestamps=[c["timestamp"] for c in candles],
            ),
        }
    except ValueError as exc:
        raise HTTPException(422, f"Unable to analyze OHLCV: {exc}") from exc


@router.get("/analysis/fibonacci")
def get_fibonacci_analysis(
    symbol: str,
    timeframe: str = "1d",
    limit: Annotated[int, Query(ge=1, le=5000)] = 500,
    lookback: Annotated[int, Query(ge=10, le=5000)] = 250,
    wing: Annotated[int, Query(ge=1, le=10)] = 2,
):
    """Deterministic Fibonacci price/time projections from confirmed OHLCV pivots."""
    candles = get_candles(symbol, timeframe, limit)
    if not candles:
        raise HTTPException(404, "No candle data found")
    try:
        analysis = fibonacci.analyze_fibonacci(
            [c["high"] for c in candles],
            [c["low"] for c in candles],
            [c["close"] for c in candles],
            timestamps=[c["timestamp"] for c in candles],
            lookback=lookback,
            wing=wing,
        )
        return {
            "symbol": symbol.upper(),
            "timeframe": timeframe,
            "data_source": sorted({c["source"] for c in candles}),
            "analysis": analysis,
        }
    except ValueError as exc:
        raise HTTPException(422, f"Unable to calculate Fibonacci levels: {exc}") from exc


@router.get("/analysis/elliott")
def get_elliott_analysis(
    symbol: str,
    timeframe: str = "1d",
    limit: Annotated[int, Query(ge=1, le=5000)] = 500,
    lookback: Annotated[int, Query(ge=10, le=5000)] = 250,
    wing: Annotated[int, Query(ge=1, le=10)] = 2,
):
    """Rule-based Elliott five-wave impulse hypothesis from confirmed OHLCV pivots."""
    candles = get_candles(symbol, timeframe, limit)
    if not candles:
        raise HTTPException(404, "No candle data found")
    try:
        analysis = elliott.analyze_elliott(
            [c["high"] for c in candles],
            [c["low"] for c in candles],
            [c["close"] for c in candles],
            timestamps=[c["timestamp"] for c in candles],
            lookback=lookback,
            wing=wing,
        )
        return {
            "symbol": symbol.upper(),
            "timeframe": timeframe,
            "data_source": sorted({c["source"] for c in candles}),
            "analysis": analysis,
        }
    except ValueError as exc:
        raise HTTPException(422, f"Unable to evaluate Elliott structure: {exc}") from exc


@router.get("/analysis/volume-flow")
def get_volume_flow_analysis(
    symbol: str,
    timeframe: str = "1d",
    limit: Annotated[int, Query(ge=1, le=5000)] = 500,
    window: Annotated[int, Query(ge=2, le=250)] = 20,
):
    """Deterministic OHLCV money-flow and accumulation/distribution observations."""
    candles = get_candles(symbol, timeframe, limit)
    if not candles:
        raise HTTPException(404, "No candle data found")
    try:
        analysis = volume_flow.analyze_volume_flow(
            [c["high"] for c in candles],
            [c["low"] for c in candles],
            [c["close"] for c in candles],
            [c["volume"] for c in candles],
            timestamps=[c["timestamp"] for c in candles],
            window=window,
        )
        return {
            "symbol": symbol.upper(),
            "timeframe": timeframe,
            "data_source": sorted({c["source"] for c in candles}),
            "analysis": analysis,
        }
    except ValueError as exc:
        raise HTTPException(422, f"Unable to analyze volume flow: {exc}") from exc



@router.get("/analysis/report")
def get_analysis_report(
    symbol: str,
    timeframe: str = "1d",
    limit: Annotated[int, Query(ge=1, le=5000)] = 500,
):
    """Combined deterministic technical report and conditional market scenarios."""
    candles = get_candles(symbol, timeframe, limit)
    if not candles:
        raise HTTPException(404, "No candle data found")
    try:
        active_rules = rule_registry.get_active_version()
        return {
            "symbol": symbol.upper(),
            "timeframe": timeframe,
            "report": analysis_report.build_analysis_report(
                candles,
                rule_config=active_rules["config"],
                rule_version=active_rules["version"],
                rule_config_sha256=active_rules["config_sha256"],
            ),
        }
    except ValueError as exc:
        raise HTTPException(422, f"Unable to build analysis report: {exc}") from exc


@router.get("/watchlist")
def get_watchlist():
    """Return locally persisted symbols in user-defined order."""
    return {"items": watchlist.list_watchlist()}


@router.post("/watchlist", status_code=201)
def add_watchlist_symbol(symbol: Annotated[str, Query(min_length=3, max_length=12, pattern=r"^[A-Za-z0-9.]+$")]):
    normalized, error = watchlist.add_symbol(symbol)
    if error == "symbol_not_found":
        raise HTTPException(404, "Create or import the symbol before adding it to the watchlist")
    if error == "already_exists":
        raise HTTPException(409, "Symbol is already in the watchlist")
    return {"symbol": normalized, "status": "added"}


@router.delete("/watchlist/{symbol}")
def delete_watchlist_symbol(symbol: str):
    if not watchlist.remove_symbol(symbol):
        raise HTTPException(404, "Symbol is not in the watchlist")
    return {"symbol": symbol.upper(), "status": "removed"}


@router.put("/watchlist/order")
def put_watchlist_order(symbols: list[str] = Body(..., min_length=0, max_length=500)):
    if any(not item or len(item) > 12 for item in symbols):
        raise HTTPException(422, "Each symbol must contain 1 to 12 characters")
    success, error = watchlist.reorder_symbols(symbols)
    if error == "duplicate_symbols":
        raise HTTPException(422, "Order contains duplicate symbols")
    if error == "must_include_exact_watchlist":
        raise HTTPException(422, "Order must contain every current watchlist symbol exactly once")
    return {"status": "updated", "symbols": [item.upper() for item in symbols]}



@router.post("/knowledge/documents", status_code=201)
async def upload_knowledge_document(
    file: UploadFile = File(...),
    source: Annotated[str, Query(min_length=1, max_length=100)] = "user_upload",
    title: Annotated[str | None, Query(max_length=200)] = None,
    category: Annotated[str, Query(max_length=40)] = "other",
):
    """Extract and index a local TXT/Markdown/CSV/PDF document into SQLite."""
    raw = await file.read(10_485_761)
    if len(raw) > knowledge_base.MAX_UPLOAD_BYTES:
        raise HTTPException(413, "Document exceeds the 10 MB upload limit")
    try:
        result = knowledge_base.ingest_document(
            file.filename or "", raw, source=source, title=title, category=category
        )
    except knowledge_base.KnowledgeBaseError as exc:
        raise HTTPException(400, str(exc)) from exc
    if result["status"] == "duplicate":
        raise HTTPException(409, {
            "message": "This exact document has already been indexed",
            "document_id": result["id"],
            "content_sha256": result["content_sha256"],
        })
    return result


@router.get("/knowledge/documents")
def list_knowledge_documents(
    limit: Annotated[int, Query(ge=1, le=500)] = 100,
    offset: Annotated[int, Query(ge=0)] = 0,
    category: Annotated[str | None, Query(max_length=40)] = None,
):
    """List indexed knowledge documents without returning their full text."""
    try:
        return knowledge_base.list_documents(limit=limit, offset=offset, category=category)
    except knowledge_base.KnowledgeBaseError as exc:
        raise HTTPException(400, str(exc)) from exc


@router.get("/knowledge/documents/{document_id}")
def get_knowledge_document(document_id: int):
    """Return document metadata and its ordered text chunks."""
    result = knowledge_base.get_document(document_id, include_chunks=True)
    if result is None:
        raise HTTPException(404, "Knowledge document not found")
    return result


@router.get("/knowledge/citations/{document_id}/{chunk_index}")
def resolve_knowledge_citation(document_id: int, chunk_index: int):
    """Resolve kb:document_id:chunk_index to the exact immutable source locator."""
    result = knowledge_base.get_citation(document_id, chunk_index)
    if result is None:
        raise HTTPException(404, "Knowledge citation not found")
    return result


@router.delete("/knowledge/documents/{document_id}")
def delete_knowledge_document(document_id: int):
    """Delete a document and cascade-delete all of its chunks."""
    if not knowledge_base.delete_document(document_id):
        raise HTTPException(404, "Knowledge document not found")
    return {"document_id": document_id, "status": "deleted"}


@router.get("/knowledge/search")
def search_knowledge_documents(
    q: Annotated[str, Query(min_length=1, max_length=500)],
    top_k: Annotated[int, Query(ge=1, le=20)] = 5,
    category: Annotated[str | None, Query(max_length=40)] = None,
):
    """Retrieve local knowledge chunks with stable source citations."""
    try:
        result = knowledge_retrieval.search_knowledge(q, top_k=top_k, category=category)
        result["retrieval_context"] = knowledge_retrieval.build_retrieval_context(result)
        return result
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc


@router.get("/analysis/rules")
def list_analysis_rule_versions(
    limit: Annotated[int, Query(ge=1, le=500)] = 100,
    offset: Annotated[int, Query(ge=0)] = 0,
):
    """List immutable rule configuration versions and their activation state."""
    return rule_registry.list_versions(limit=limit, offset=offset)


@router.get("/analysis/rules/active")
def get_active_analysis_rules():
    """Return the single active rule metadata/configuration version."""
    return rule_registry.get_active_version()


@router.get("/analysis/rules/history")
def get_analysis_rule_activation_history(
    limit: Annotated[int, Query(ge=1, le=500)] = 100,
    offset: Annotated[int, Query(ge=0)] = 0,
):
    """Return append-only activation events, newest first."""
    return rule_registry.list_activation_history(limit=limit, offset=offset)


@router.post("/analysis/rules", status_code=201)
def create_analysis_rule_version(payload: dict = Body(...)):
    """Create an immutable draft; existing versions can never be overwritten."""
    try:
        return rule_registry.create_version(
            version=payload.get("version", ""),
            name=payload.get("name", ""),
            description=payload.get("description", ""),
            config=payload.get("config", {}),
        )
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from exc


@router.post("/analysis/rules/{version}/activate")
def activate_analysis_rule_version(version: str):
    """Activate a stored version and archive the previous active version."""
    try:
        return rule_registry.activate_version(version)
    except KeyError as exc:
        raise HTTPException(404, str(exc)) from exc


@router.get("/analysis/rules/compare")
def compare_analysis_rule_versions(
    symbol: str,
    versions: Annotated[str, Query(min_length=5, max_length=100)],
    timeframe: Annotated[str, Query(min_length=2, max_length=8)] = "1d",
    limit: Annotated[int, Query(ge=20, le=5000)] = 500,
):
    """Compare 2-5 immutable rule versions against the same stored OHLCV history."""
    requested = [item.strip() for item in versions.split(",") if item.strip()]
    if not 2 <= len(requested) <= 5 or len(set(requested)) != len(requested):
        raise HTTPException(422, "Provide 2 to 5 unique comma-separated versions")
    candles = get_candles(symbol, timeframe, limit)
    if not candles:
        raise HTTPException(404, "No candle data found")
    stored_versions = []
    for version in requested:
        item = rule_registry.get_version(version)
        if item is None:
            raise HTTPException(404, f"Unknown analysis rule version: {version}")
        stored_versions.append(item)
    try:
        return {
            "symbol": symbol.upper(),
            "timeframe": timeframe,
            "comparison": rule_evaluation.compare_rule_versions(candles, stored_versions),
        }
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from exc
