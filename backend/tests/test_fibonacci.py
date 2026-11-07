import unittest

from app.fibonacci import analyze_fibonacci


class FibonacciTests(unittest.TestCase):
    def make_swing(self):
        closes = [10, 11, 12, 13, 14, 13, 12, 11, 10, 11, 12, 13, 14, 15, 14, 13]
        highs = [value + 0.5 for value in closes]
        lows = [value - 0.5 for value in closes]
        timestamps = [f"2026-01-{index + 1:02d}T00:00:00+07:00" for index in range(len(closes))]
        return highs, lows, closes, timestamps

    def test_bullish_retracement_extension_and_time(self):
        highs, lows, closes, timestamps = self.make_swing()
        result = analyze_fibonacci(highs, lows, closes, timestamps)
        self.assertEqual(result["status"], "ok")
        self.assertEqual(result["direction"], "bullish")
        self.assertEqual(result["swing"]["start"]["type"], "low")
        self.assertEqual(result["swing"]["end"]["type"], "high")
        self.assertAlmostEqual(result["price"]["retracements"][2]["price"], 12.5)
        self.assertAlmostEqual(result["price"]["extensions"][2]["price"], 19.208)
        self.assertEqual(result["time"]["unit"], "trading_bars")
        self.assertEqual(result["time"]["projections"][3]["projected_bar_index"], 18)

    def test_future_projection_is_bar_offset_not_calendar_date(self):
        highs, lows, closes, timestamps = self.make_swing()
        result = analyze_fibonacci(highs, lows, closes, timestamps)
        future = [item for item in result["time"]["projections"] if item["position"] == "future"]
        self.assertTrue(future)
        self.assertNotIn("projected_timestamp", future[0])
        self.assertGreater(future[0]["bars_from_latest"], 0)

    def test_no_confirmed_swing_is_explicit(self):
        closes = [float(index + 10) for index in range(30)]
        highs = [value + 1 for value in closes]
        lows = [value - 1 for value in closes]
        result = analyze_fibonacci(highs, lows, closes)
        self.assertEqual(result["status"], "no_confirmed_swing")

    def test_rejects_invalid_ohlc_and_timestamp_length(self):
        with self.assertRaises(ValueError):
            analyze_fibonacci([10, 11], [9, 10], [11, 10])
        with self.assertRaises(ValueError):
            analyze_fibonacci([10, 11], [9, 10], [9.5, 10], ["only-one"])

    def test_bearish_swing_direction(self):
        closes = [15, 14, 13, 12, 11, 12, 13, 14, 15, 14, 13, 12, 11, 10, 11, 12]
        highs = [value + 0.5 for value in closes]
        lows = [value - 0.5 for value in closes]
        result = analyze_fibonacci(highs, lows, closes)
        self.assertEqual(result["status"], "ok")
        self.assertEqual(result["direction"], "bearish")
        self.assertEqual(result["swing"]["start"]["type"], "high")
        self.assertEqual(result["swing"]["end"]["type"], "low")


if __name__ == "__main__":
    unittest.main()
