"""Persistent local watchlist operations backed by SQLite."""
from .db import connection


def list_watchlist():
    with connection() as conn:
        rows = conn.execute(
            """SELECT w.symbol, s.name, s.exchange, s.sector, w.sort_order, w.added_at,
                      (SELECT COUNT(*) FROM candles c WHERE c.symbol=w.symbol) AS candle_count
               FROM watchlist w JOIN symbols s ON s.symbol=w.symbol
               ORDER BY w.sort_order, w.added_at, w.symbol"""
        ).fetchall()
    return [dict(row) for row in rows]


def add_symbol(symbol):
    normalized = symbol.strip().upper()
    with connection() as conn:
        if not conn.execute("SELECT 1 FROM symbols WHERE symbol=?", (normalized,)).fetchone():
            return None, "symbol_not_found"
        if conn.execute("SELECT 1 FROM watchlist WHERE symbol=?", (normalized,)).fetchone():
            return None, "already_exists"
        next_order = conn.execute("SELECT COALESCE(MAX(sort_order), -1) + 1 FROM watchlist").fetchone()[0]
        conn.execute("INSERT INTO watchlist(symbol, sort_order) VALUES(?, ?)", (normalized, next_order))
    return normalized, None


def remove_symbol(symbol):
    normalized = symbol.strip().upper()
    with connection() as conn:
        cursor = conn.execute("DELETE FROM watchlist WHERE symbol=?", (normalized,))
        if cursor.rowcount == 0:
            return False
        rows = conn.execute("SELECT symbol FROM watchlist ORDER BY sort_order, added_at, symbol").fetchall()
        for index, row in enumerate(rows):
            conn.execute("UPDATE watchlist SET sort_order=? WHERE symbol=?", (index, row["symbol"]))
    return True


def reorder_symbols(symbols):
    normalized = [item.strip().upper() for item in symbols]
    if len(normalized) != len(set(normalized)):
        return False, "duplicate_symbols"
    with connection() as conn:
        current = {row["symbol"] for row in conn.execute("SELECT symbol FROM watchlist").fetchall()}
        if set(normalized) != current:
            return False, "must_include_exact_watchlist"
        for index, symbol in enumerate(normalized):
            conn.execute("UPDATE watchlist SET sort_order=? WHERE symbol=?", (index, symbol))
    return True, None
