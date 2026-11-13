"""SQLite online-backup and isolated-restore regression tests.

All database files and bootstrap-secret fixtures live under TemporaryDirectory.
These tests never access Docker volumes or a deployment database.
"""
from __future__ import annotations

import hashlib
from contextlib import closing
import shutil
import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from app import auth, db, knowledge_base, rule_registry, training_room


_REQUIRED_TABLES = {
    "symbols", "candles", "watchlist", "knowledge_documents",
    "knowledge_chunks", "auth_bootstrap", "auth_users", "auth_sessions",
    "analysis_rule_versions", "analysis_rule_activation_history",
    "training_examples", "training_example_review_events",
    "training_example_quality_reviews",
}


class BackupValidationError(ValueError):
    """A candidate backup is absent, malformed, or not a SmartStock database."""


def _verify_backup(path: Path) -> dict[str, object]:
    """Fail closed on incomplete files, non-SQLite bytes, or invalid DB contents."""
    if not path.is_file():
        raise BackupValidationError("backup file is missing")
    if path.stat().st_size == 0:
        raise BackupValidationError("backup file is empty")
    try:
        with path.open("rb") as handle:
            if handle.read(16) != b"SQLite format 3\x00":
                raise BackupValidationError("backup is not a SQLite database")
        uri = path.resolve().as_uri() + "?mode=ro"
        with closing(sqlite3.connect(uri, uri=True)) as conn:
            integrity = [row[0] for row in conn.execute("PRAGMA integrity_check")]
            if integrity != ["ok"]:
                raise BackupValidationError("SQLite integrity_check failed")
            foreign_key_errors = conn.execute("PRAGMA foreign_key_check").fetchall()
            if foreign_key_errors:
                raise BackupValidationError("SQLite foreign_key_check failed")
            tables = {
                row[0]
                for row in conn.execute(
                    "SELECT name FROM sqlite_master WHERE type='table'"
                )
            }
            if _REQUIRED_TABLES - tables:
                raise BackupValidationError(
                    "backup is missing required application tables"
                )
            return {
                "integrity": integrity[0],
                "foreign_key_errors": len(foreign_key_errors),
                "tables": tuple(sorted(tables)),
            }
    except BackupValidationError:
        raise
    except (OSError, sqlite3.DatabaseError, ValueError) as exc:
        raise BackupValidationError("backup cannot be opened or verified") from exc


def _database_manifest(path: Path) -> dict[str, object]:
    """Capture deterministic schema and application rows without exposing secrets."""
    with closing(sqlite3.connect(path)) as conn:
        schema = tuple(
            tuple(row)
            for row in conn.execute(
                """SELECT type,name,tbl_name,sql FROM sqlite_master
                   WHERE type IN ('table','index','trigger') AND sql IS NOT NULL
                   ORDER BY type,name"""
            )
        )
        table_names = [
            row[0]
            for row in conn.execute(
                """SELECT name FROM sqlite_master WHERE type='table'
                   AND name NOT LIKE 'sqlite_%' ORDER BY name"""
            )
        ]
        rows = {}
        for table in table_names:
            rows[table] = tuple(
                tuple(row)
                for row in conn.execute(f'SELECT * FROM "{table}" ORDER BY rowid')
            )
        sequence_exists = conn.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='sqlite_sequence'"
        ).fetchone()
        sequence = (
            tuple(tuple(row) for row in conn.execute(
                "SELECT name,seq FROM sqlite_sequence ORDER BY name"
            ))
            if sequence_exists else ()
        )
    return {"schema": schema, "rows": rows, "sqlite_sequence": sequence}


def _online_backup(source_path: Path, destination_path: Path) -> None:
    destination_path.parent.mkdir(parents=True, exist_ok=True)
    with closing(sqlite3.connect(source_path)) as source:
        with closing(sqlite3.connect(destination_path)) as destination:
            source.backup(destination)


def _bootstrap_pair_matches(database_path: Path, secret_path: Path) -> bool:
    """Validate an unconsumed pre-owner DB and its matching private secret file."""
    if not database_path.is_file() or not secret_path.is_file():
        return False
    try:
        secret = secret_path.read_text(encoding="utf-8").strip()
        if not secret:
            return False
        with sqlite3.connect(database_path) as conn:
            if conn.execute("SELECT 1 FROM auth_users LIMIT 1").fetchone():
                return False
            row = conn.execute(
                "SELECT secret_sha256,consumed_at FROM auth_bootstrap WHERE id=1"
            ).fetchone()
        return bool(
            row and row[1] is None
            and hashlib.sha256(secret.encode("utf-8")).hexdigest() == row[0]
        )
    except (OSError, sqlite3.DatabaseError, UnicodeError):
        return False


class SQLiteBackupRestoreTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.source_path = self.root / "source" / "smartstock.db"
        self.db_patch = patch("app.db.DB_PATH", str(self.source_path))
        self.db_patch.start()
        db.init_db()
        auth.ensure_bootstrap_secret()
        self.bootstrap_secret = auth.read_bootstrap_secret()

    def tearDown(self):
        self.db_patch.stop()
        self.temp_dir.cleanup()

    def _seed_application_data(self) -> tuple[str, int, int]:
        with db.connection() as conn:
            conn.execute(
                "INSERT INTO symbols(symbol,name,exchange,sector) VALUES(?,?,?,?)",
                ("TST1", "Synthetic Test Instrument", "HOSE", "test-only"),
            )
            conn.execute(
                """INSERT INTO candles
                   (symbol,timeframe,timestamp,open,high,low,close,volume,source)
                   VALUES(?,?,?,?,?,?,?,?,?)""",
                ("TST1", "1D", "2026-01-02T00:00:00", 10, 12, 9, 11, 1234,
                 "synthetic_test_fixture"),
            )
            conn.execute(
                "INSERT INTO watchlist(symbol,sort_order) VALUES(?,?)",
                ("TST1", 1),
            )

        document = knowledge_base.ingest_document(
            "restore-fixture.md",
            b"# Synthetic restore fixture\nThis content exists only in an isolated test database.\n",
            source="automated_test_fixture",
            title="Synthetic restore fixture",
            category="technical_analysis",
        )
        citation = f"kb:{document['id']}:0"

        auth.create_first_owner(
            "restore_owner", "a-long-test-password", self.bootstrap_secret
        )
        session = auth.login("restore_owner", "a-long-test-password")
        token = session["access_token"]
        owner = auth.authenticate(token)
        self.assertIsNotNone(owner)
        owner_id = owner["id"]

        example = training_room.create_example({
            "question": "How is this synthetic restore fixture used?",
            "expected_answer": "It verifies that isolated SQLite restore preserves reviewed training data.",
            "topic": "backup_restore_test",
            "citation_ids": [citation],
        })
        approved = training_room.approve_example(example["id"], owner_id)
        self.assertEqual(approved["status"], "approved")
        training_room.create_quality_review(
            example["id"], 95, "qa-quality-v1",
            "Synthetic quality review retained across the backup and restore test.",
            owner_id,
        )

        rule_registry.ensure_default_version()
        rule_registry.create_version(
            "1.1.0", "Synthetic restore rule", "Test-only rule version.",
            {"fibonacci": {"lookback": 120, "wing": 2}},
        )
        rule_registry.activate_version("1.1.0")
        return token, document["id"], example["id"]

    def test_online_backup_restore_preserves_application_state_and_revokes_old_sessions(self):
        token, document_id, example_id = self._seed_application_data()
        before = _database_manifest(self.source_path)
        source_sha_before = hashlib.sha256(self.source_path.read_bytes()).hexdigest()

        backup_path = self.root / "backup" / "smartstock.db"
        _online_backup(self.source_path, backup_path)
        verification = _verify_backup(backup_path)
        self.assertEqual(verification["integrity"], "ok")
        self.assertEqual(verification["foreign_key_errors"], 0)

        restored_path = self.root / "restore" / "smartstock.db"
        restored_path.parent.mkdir(parents=True)
        shutil.copy2(backup_path, restored_path)
        _verify_backup(restored_path)
        self.assertNotEqual(restored_path.resolve(), self.source_path.resolve())
        self.assertEqual(before, _database_manifest(restored_path))

        with patch("app.db.DB_PATH", str(restored_path)):
            db.init_db()
            self.assertEqual(before, _database_manifest(restored_path))
            self.assertIsNotNone(auth.authenticate(token))

            document = knowledge_base.get_document(document_id, include_chunks=True)
            self.assertEqual(document["title"], "Synthetic restore fixture")
            self.assertEqual(len(document["chunks"]), 1)
            self.assertIsNotNone(knowledge_base.get_citation(document_id, 0))

            examples = training_room.list_examples(limit=20)
            self.assertEqual(examples["total"], 1)
            self.assertEqual(examples["items"][0]["status"], "approved")
            events = training_room.list_review_events(example_id)
            self.assertEqual(events["total"], 1)
            self.assertEqual(events["items"][0]["action"], "approved")
            quality = training_room.list_quality_reviews(example_id)
            self.assertEqual(len(quality), 1)
            self.assertEqual(quality[0]["score"], 95)

            active_rule = rule_registry.get_active_version()
            self.assertEqual(active_rule["version"], "1.1.0")
            self.assertEqual(rule_registry.list_activation_history()["total"], 2)
            with db.connection() as conn:
                candle = conn.execute(
                    "SELECT close,volume,source FROM candles WHERE symbol='TST1'"
                ).fetchone()
                self.assertEqual(tuple(candle), (11.0, 1234.0, "synthetic_test_fixture"))
                self.assertEqual(
                    conn.execute("SELECT symbol FROM watchlist").fetchone()[0], "TST1"
                )
                bootstrap = conn.execute(
                    "SELECT consumed_at FROM auth_bootstrap WHERE id=1"
                ).fetchone()
                self.assertIsNotNone(bootstrap["consumed_at"])
                self.assertEqual(
                    conn.execute("SELECT COUNT(*) FROM auth_users").fetchone()[0], 1
                )
                conn.execute(
                    """UPDATE auth_sessions SET revoked_at=CURRENT_TIMESTAMP
                       WHERE revoked_at IS NULL"""
                )
                self.assertEqual(
                    conn.execute(
                        "SELECT COUNT(*) FROM auth_sessions WHERE revoked_at IS NULL"
                    ).fetchone()[0], 0
                )
                self.assertIsNotNone(conn.execute(
                    """SELECT 1 FROM sqlite_master WHERE type='trigger'
                       AND name='trg_training_review_events_no_update'"""
                ).fetchone())
                self.assertIsNotNone(conn.execute(
                    """SELECT 1 FROM sqlite_master WHERE type='index'
                       AND name='idx_candles_symbol_time'"""
                ).fetchone())
                self.assertEqual(conn.execute("PRAGMA integrity_check").fetchone()[0], "ok")
                self.assertEqual(conn.execute("PRAGMA foreign_key_check").fetchall(), [])

            # A pre-backup bearer token is invalid only after the documented
            # restore-time revocation statement has been applied.
            self.assertIsNone(auth.authenticate(token))
            with db.connection() as conn:
                conn.execute(
                    "INSERT INTO symbols(symbol,name,exchange) VALUES('TST2','Next ID','HNX')"
                )
                self.assertEqual(
                    conn.execute("SELECT id FROM knowledge_documents").fetchone()[0],
                    document_id,
                )

        self.assertEqual(
            hashlib.sha256(self.source_path.read_bytes()).hexdigest(),
            source_sha_before,
        )
        self.assertFalse((restored_path.parent / "bootstrap.secret").exists())
        self.assertFalse(auth._bootstrap_secret_path().exists())

    def test_missing_empty_truncated_and_non_sqlite_backups_fail_closed(self):
        missing = self.root / "missing.db"
        empty = self.root / "empty.db"
        non_sqlite = self.root / "not-sqlite.db"
        truncated = self.root / "truncated.db"
        empty.touch()
        non_sqlite.write_bytes(b"not a sqlite database")
        self._seed_application_data()
        valid = self.root / "valid.db"
        _online_backup(self.source_path, valid)
        raw = valid.read_bytes()
        truncated.write_bytes(raw[: min(100, len(raw) // 2)])

        for candidate in (missing, empty, truncated, non_sqlite):
            with self.subTest(candidate=candidate.name):
                with self.assertRaises(BackupValidationError):
                    _verify_backup(candidate)

    def test_pre_owner_bootstrap_secret_must_match_database_snapshot(self):
        source_secret_path = auth._bootstrap_secret_path()
        self.assertTrue(_bootstrap_pair_matches(self.source_path, source_secret_path))

        backup_path = self.root / "pre-owner-backup.db"
        _online_backup(self.source_path, backup_path)
        restored_secret = self.root / "pre-owner-restore" / "bootstrap.secret"
        restored_secret.parent.mkdir(parents=True)
        shutil.copy2(source_secret_path, restored_secret)
        self.assertTrue(_bootstrap_pair_matches(backup_path, restored_secret))

        wrong_secret = restored_secret.parent / "wrong.secret"
        wrong_secret.write_text("a-different-test-only-secret-value", encoding="utf-8")
        self.assertFalse(_bootstrap_pair_matches(backup_path, wrong_secret))
        self.assertFalse(
            _bootstrap_pair_matches(backup_path, restored_secret.parent / "missing.secret")
        )


if __name__ == "__main__":
    unittest.main()
