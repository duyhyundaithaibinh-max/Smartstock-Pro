import os
import sqlite3
from pathlib import Path
from contextlib import contextmanager

DB_PATH = os.getenv("SMARTSTOCK_DB_PATH", "data/smartstock.db")


def _connect():
    path = Path(DB_PATH)
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


@contextmanager
def connection():
    conn = _connect()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def init_db():
    with connection() as conn:
        conn.executescript("""
        CREATE TABLE IF NOT EXISTS symbols (
            symbol TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            exchange TEXT NOT NULL CHECK(exchange IN ('HOSE','HNX','UPCOM')),
            sector TEXT,
            updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        CREATE TABLE IF NOT EXISTS candles (
            symbol TEXT NOT NULL,
            timeframe TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            open REAL NOT NULL,
            high REAL NOT NULL,
            low REAL NOT NULL,
            close REAL NOT NULL,
            volume REAL NOT NULL,
            source TEXT NOT NULL,
            fetched_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY(symbol, timeframe, timestamp),
            FOREIGN KEY(symbol) REFERENCES symbols(symbol)
        );
        CREATE INDEX IF NOT EXISTS idx_candles_symbol_time
            ON candles(symbol, timeframe, timestamp);
        """)
