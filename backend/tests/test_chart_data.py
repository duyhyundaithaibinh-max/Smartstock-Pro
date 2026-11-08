import unittest

from app.chart_data import aggregate_candles


class ChartAggregationTests(unittest.TestCase):
    def setUp(self):
        self.candles = [
            {"timestamp": "2026-01-05T15:00:00+07:00", "open": 10, "high": 12, "low": 9, "close": 11, "volume": 100, "source": "csv-a"},
            {"timestamp": "2026-01-06T15:00:00+07:00", "open": 11, "high": 13, "low": 10, "close": 12, "volume": 120, "source": "csv-a"},
            {"timestamp": "2026-01-12T15:00:00+07:00", "open": 12, "high": 14, "low": 11, "close": 13, "volume": 150, "source": "csv-b"},
            {"timestamp": "2026-02-02T15:00:00+07:00", "open": 13, "high": 15, "low": 12, "close": 14, "volume": 200, "source": "csv-b"},
        ]

    def test_daily_preserves_source_candles_without_filling_gaps(self):
        result = aggregate_candles(self.candles, "daily")
        self.assertEqual(len(result), 4)
        self.assertEqual(result[0]["close"], 11)
        self.assertEqual(result[0]["sessions"], 1)

    def test_weekly_aggregates_ohlcv_and_keeps_source_provenance(self):
        result = aggregate_candles(self.candles, "weekly")
        self.assertEqual(len(result), 3)
        self.assertEqual(result[0]["open"], 10)
        self.assertEqual(result[0]["high"], 13)
        self.assertEqual(result[0]["low"], 9)
        self.assertEqual(result[0]["close"], 12)
        self.assertEqual(result[0]["volume"], 220)
        self.assertEqual(result[0]["sources"], ["csv-a"])
        self.assertEqual(result[0]["sessions"], 2)

    def test_monthly_groups_calendar_months(self):
        result = aggregate_candles(self.candles, "monthly")
        self.assertEqual(len(result), 2)
        self.assertEqual(result[0]["volume"], 370)
        self.assertEqual(result[0]["close"], 13)
        self.assertEqual(result[1]["open"], 13)

    def test_empty_data_returns_empty_and_invalid_period_rejected(self):
        self.assertEqual(aggregate_candles([]), [])
        with self.assertRaises(ValueError):
            aggregate_candles(self.candles, "quarterly")


if __name__ == "__main__":
    unittest.main()
