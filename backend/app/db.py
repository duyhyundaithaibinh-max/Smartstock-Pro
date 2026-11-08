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
        CREATE TABLE IF NOT EXISTS knowledge_documents (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            filename TEXT NOT NULL,
            title TEXT NOT NULL,
            mime_type TEXT NOT NULL,
            source TEXT NOT NULL,
            size_bytes INTEGER NOT NULL CHECK(size_bytes > 0),
            content_sha256 TEXT NOT NULL UNIQUE,
            character_count INTEGER NOT NULL CHECK(character_count > 0),
            chunk_count INTEGER NOT NULL CHECK(chunk_count > 0),
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        CREATE TABLE IF NOT EXISTS knowledge_chunks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            document_id INTEGER NOT NULL,
            chunk_index INTEGER NOT NULL CHECK(chunk_index >= 0),
            content TEXT NOT NULL,
            char_start INTEGER NOT NULL CHECK(char_start >= 0),
            char_end INTEGER NOT NULL CHECK(char_end > char_start),
            UNIQUE(document_id, chunk_index),
            FOREIGN KEY(document_id) REFERENCES knowledge_documents(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_knowledge_chunks_document
            ON knowledge_chunks(document_id, chunk_index);
        CREATE TABLE IF NOT EXISTS analysis_rule_versions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            version TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL,
            description TEXT NOT NULL,
            config_json TEXT NOT NULL,
            config_sha256 TEXT NOT NULL,
            status TEXT NOT NULL CHECK(status IN ('draft','active','archived')),
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            activated_at TEXT
        );
        CREATE UNIQUE INDEX IF NOT EXISTS idx_one_active_analysis_rule
            ON analysis_rule_versions(status) WHERE status='active';
        CREATE TABLE IF NOT EXISTS analysis_rule_activation_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            version TEXT NOT NULL,
            config_sha256 TEXT NOT NULL,
            previous_version TEXT,
            activated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY(version) REFERENCES analysis_rule_versions(version)
        );
        CREATE INDEX IF NOT EXISTS idx_rule_activation_history_time
            ON analysis_rule_activation_history(activated_at DESC, id DESC);
        CREATE TRIGGER IF NOT EXISTS trg_rule_activation_history_no_update
        BEFORE UPDATE ON analysis_rule_activation_history
        BEGIN
            SELECT RAISE(ABORT, 'analysis rule activation history is append-only');
        END;
        CREATE TRIGGER IF NOT EXISTS trg_rule_activation_history_no_delete
        BEFORE DELETE ON analysis_rule_activation_history
        BEGIN
            SELECT RAISE(ABORT, 'analysis rule activation history is append-only');
        END;
        CREATE TABLE IF NOT EXISTS watchlist (
            symbol TEXT PRIMARY KEY,
            sort_order INTEGER NOT NULL DEFAULT 0,
            added_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY(symbol) REFERENCES symbols(symbol) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS training_examples (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            question TEXT NOT NULL,
            expected_answer TEXT NOT NULL,
            topic TEXT NOT NULL DEFAULT 'general',
            citation_ids TEXT NOT NULL,
            status TEXT NOT NULL CHECK(status IN ('draft','approved')) DEFAULT 'draft',
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        CREATE INDEX IF NOT EXISTS idx_training_examples_status_created
            ON training_examples(status, created_at);
        """)
        # Safe additive migration for databases created before document categories.
        document_columns = {
            row["name"] for row in conn.execute("PRAGMA table_info(knowledge_documents)").fetchall()
        }
        if "category" not in document_columns:
            conn.execute(
                "ALTER TABLE knowledge_documents ADD COLUMN category TEXT NOT NULL DEFAULT 'other'"
            )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_knowledge_documents_category "
            "ON knowledge_documents(category, created_at DESC)"
        )
