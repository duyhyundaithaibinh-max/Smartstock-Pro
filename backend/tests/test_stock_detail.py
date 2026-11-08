import unittest

from app.stock_detail import build_stock_detail


class StockDetailTests(unittest.TestCase):
    def make_candles(self, count=60):
        rows = []
        for i in range(count):
            close = 20 + i * 0.1
            rows.append({
                "timestamp": f"2026-01-{(i % 28) + 1:02d}T15:00:00+07:00",
                "open": close - 0.05,
                "high": close + 0.2,
                "low": close - 0.2,
                "close": close,
                "volume": 1000 + i * 10,
                "source": "csv-fixture",
            })
        return rows

    def test_detail_contains_indicators_zones_liquidity_and_provenance(self):
        result = build_stock_detail("CTR", {
            "symbol": "CTR", "name": "Test", "exchange": "HOSE", "sector": "Technology"
        }, self.make_candles())
        self.assertEqual(result["status"], "ok")
        self.assertIsNotNone(result["indicators"]["rsi14"])
        self.assertIsNotNone(result["indicators"]["macd"])
        self.assertEqual(result["trend_and_zones"]["status"], "ok")
        self.assertEqual(result["liquidity"]["sessions_used"], 20)
        self.assertEqual(result["data_quality"]["sources"], ["csv-fixture"])
        self.assertEqual(result["data_quality"]["price_adjustment"], "unknown")

    def test_short_history_keeps_missing_values_explicit(self):
        result = build_stock_detail("CTR", {
            "symbol": "CTR", "name": "Test", "exchange": "HOSE", "sector": None
        }, self.make_candles(10))
        self.assertEqual(result["trend_and_zones"]["status"], "insufficient_data")
        self.assertEqual(result["liquidity"]["status"], "insufficient_data")
        self.assertIsNone(result["liquidity"]["average_traded_value_20_sessions"])

    def test_no_data_does_not_invent_latest_quote(self):
        result = build_stock_detail("CTR", {
            "symbol": "CTR", "name": "Test", "exchange": "HOSE", "sector": None
        }, [])
        self.assertEqual(result["status"], "no_data")
        self.assertIsNone(result["latest"])
        self.assertEqual(result["data_quality"]["sources"], [])

    def test_unknown_symbol_rejected(self):
        with self.assertRaises(ValueError):
            build_stock_detail("CTR", None, [])


if __name__ == "__main__":
    unittest.main()
