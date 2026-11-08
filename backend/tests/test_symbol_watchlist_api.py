import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi import HTTPException

from app import db
from app.routers import market
from app.schemas import SymbolCreate


class SymbolWatchlistApiFlowTests(unittest.TestCase):
    """Contract tests for the Android create-symbol then add-watchlist flow."""

    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.patch_db = patch(
            "app.db.DB_PATH", str(Path(self.temp_dir.name) / "symbol-flow.db")
        )
        self.patch_db.start()
        db.init_db()

    def tearDown(self):
        self.patch_db.stop()
        self.temp_dir.cleanup()

    def test_create_symbol_then_add_to_watchlist(self):
        created = market.create_symbol(
            SymbolCreate(
                symbol="VGI",
                name="Viettel Global",
                exchange="UPCOM",
            )
        )
        self.assertEqual(created["symbol"], "VGI")
        self.assertEqual(created["exchange"], "UPCOM")

        added = market.add_watchlist_symbol("VGI")
        self.assertEqual(added, {"symbol": "VGI", "status": "added"})

        listed = market.get_watchlist()
        self.assertEqual(len(listed["items"]), 1)
        self.assertEqual(listed["items"][0]["symbol"], "VGI")
        self.assertEqual(listed["items"][0]["name"], "Viettel Global")
        self.assertEqual(listed["items"][0]["exchange"], "UPCOM")

    def test_duplicate_symbol_creation_returns_conflict(self):
        payload = SymbolCreate(
            symbol="CTR", name="Viettel Construction", exchange="HOSE"
        )
        market.create_symbol(payload)
        with self.assertRaises(HTTPException) as raised:
            market.create_symbol(payload)
        self.assertEqual(raised.exception.status_code, 409)

    def test_duplicate_watchlist_add_returns_conflict(self):
        market.create_symbol(
            SymbolCreate(symbol="VTP", name="Viettel Post", exchange="HOSE")
        )
        market.add_watchlist_symbol("VTP")
        with self.assertRaises(HTTPException) as raised:
            market.add_watchlist_symbol("VTP")
        self.assertEqual(raised.exception.status_code, 409)

    def test_unknown_symbol_cannot_be_added_to_watchlist(self):
        with self.assertRaises(HTTPException) as raised:
            market.add_watchlist_symbol("ABC")
        self.assertEqual(raised.exception.status_code, 404)


if __name__ == "__main__":
    unittest.main()
