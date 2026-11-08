import asyncio
import tempfile
import unittest
from io import BytesIO
from pathlib import Path
from unittest.mock import patch

from fastapi import HTTPException, UploadFile

from app import db
from app.routers import market
from app.schemas import SymbolCreate


class CsvImportContractTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.patch_db = patch(
            "app.db.DB_PATH", str(Path(self.temp_dir.name) / "csv-import.db")
        )
        self.patch_db.start()
        db.init_db()
        market.create_symbol(
            SymbolCreate(symbol="VGI", name="Viettel Global", exchange="UPCOM")
        )

    def tearDown(self):
        self.patch_db.stop()
        self.temp_dir.cleanup()

    def upload(self, csv_text):
        return UploadFile(filename="candles.csv", file=BytesIO(csv_text.encode("utf-8")))

    def test_rejects_blank_source_label(self):
        with self.assertRaises(HTTPException) as raised:
            asyncio.run(market.import_csv(
                symbol="VGI", source="   ", file=self.upload(
                    "timestamp,open,high,low,close,volume\n"
                    "2026-11-07,10,12,9,11,1000\n"
                )
            ))
        self.assertEqual(raised.exception.status_code, 422)

    def test_rejects_timezone_equivalent_duplicate_timestamps_atomically(self):
        csv_text = (
            "timestamp,open,high,low,close,volume\n"
            "2026-11-07T00:00:00+07:00,10,12,9,11,1000\n"
            "2026-11-06T17:00:00Z,11,13,10,12,1200\n"
        )
        with self.assertRaises(HTTPException) as raised:
            asyncio.run(market.import_csv(
                symbol="VGI", source="user_csv", file=self.upload(csv_text)
            ))
        self.assertEqual(raised.exception.status_code, 400)
        with db.connection() as conn:
            count = conn.execute("SELECT COUNT(*) FROM candles").fetchone()[0]
        self.assertEqual(count, 0)

    def test_valid_import_trims_and_persists_provenance(self):
        csv_text = (
            "timestamp,open,high,low,close,volume\n"
            "2026-11-07,10,12,9,11,1000\n"
        )
        result = asyncio.run(market.import_csv(
            symbol="VGI", source="  licensed_feed  ", file=self.upload(csv_text)
        ))
        self.assertEqual(result["imported"], 1)
        with db.connection() as conn:
            row = conn.execute(
                "SELECT source FROM candles WHERE symbol='VGI'"
            ).fetchone()
        self.assertEqual(row["source"], "licensed_feed")


if __name__ == "__main__":
    unittest.main()
