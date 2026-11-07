import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from app import db, watchlist


class WatchlistTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.temp_dir.name) / "test.db"
        self.patch_db = patch("app.db.DB_PATH", str(self.db_path))
        self.patch_db.start()
        db.init_db()
        with db.connection() as conn:
            conn.executemany(
                "INSERT INTO symbols(symbol,name,exchange) VALUES(?,?,?)",
                [("CTR", "Viettel Construction", "HOSE"),
                 ("VTP", "Viettel Post", "HOSE"),
                 ("VGI", "Viettel Global", "UPCOM")],
            )

    def tearDown(self):
        self.patch_db.stop()
        self.temp_dir.cleanup()

    def test_add_list_and_duplicate(self):
        self.assertEqual(watchlist.add_symbol("ctr"), ("CTR", None))
        self.assertEqual(watchlist.add_symbol("CTR"), (None, "already_exists"))
        items = watchlist.list_watchlist()
        self.assertEqual([item["symbol"] for item in items], ["CTR"])
        self.assertEqual(items[0]["candle_count"], 0)

    def test_unknown_symbol_rejected(self):
        self.assertEqual(watchlist.add_symbol("NOPE"), (None, "symbol_not_found"))

    def test_remove_and_compact_order(self):
        for symbol in ("CTR", "VTP", "VGI"):
            watchlist.add_symbol(symbol)
        self.assertTrue(watchlist.remove_symbol("VTP"))
        self.assertEqual(
            [(item["symbol"], item["sort_order"]) for item in watchlist.list_watchlist()],
            [("CTR", 0), ("VGI", 1)],
        )
        self.assertFalse(watchlist.remove_symbol("VTP"))

    def test_reorder_requires_exact_unique_members(self):
        for symbol in ("CTR", "VTP", "VGI"):
            watchlist.add_symbol(symbol)
        self.assertEqual(watchlist.reorder_symbols(["VGI", "CTR", "VTP"]), (True, None))
        self.assertEqual([item["symbol"] for item in watchlist.list_watchlist()], ["VGI", "CTR", "VTP"])
        self.assertEqual(watchlist.reorder_symbols(["CTR", "CTR"]), (False, "duplicate_symbols"))
        self.assertEqual(watchlist.reorder_symbols(["CTR"]), (False, "must_include_exact_watchlist"))


if __name__ == "__main__":
    unittest.main()
