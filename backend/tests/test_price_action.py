import unittest

from app.price_action import analyze_price_action


class PriceActionTests(unittest.TestCase):
    def make_series(self, count=80, start=100.0, step=0.5):
        closes = [start + i * step for i in range(count)]
        highs = [value + 1 for value in closes]
        lows = [value - 1 for value in closes]
        volumes = [1000.0] * count
        return highs, lows, closes, volumes

    def test_insufficient_data_is_explicit(self):
        result = analyze_price_action([11] * 10, [9] * 10, [10] * 10, [100] * 10)
        self.assertEqual(result["status"], "insufficient_data")
        self.assertEqual(result["bars_required"], 20)

    def test_uptrend_classification(self):
        highs, lows, closes, volumes = self.make_series()
        result = analyze_price_action(highs, lows, closes, volumes)
        self.assertEqual(result["trend"]["classification"], "uptrend")
        self.assertIsNotNone(result["trend"]["ema50"])

    def test_breakout_requires_price_and_volume_confirmation(self):
        highs, lows, closes, volumes = self.make_series()
        prior_high = max(highs[-21:-1])
        closes[-1] = prior_high + 3
        highs[-1] = closes[-1] + 1
        lows[-1] = closes[-1] - 1
        volumes[-1] = 1500
        result = analyze_price_action(highs, lows, closes, volumes)
        self.assertEqual(result["breakout"]["state"], "confirmed_bullish")
        self.assertGreaterEqual(result["breakout"]["volume_ratio"], 1.2)

    def test_price_break_without_volume_is_unconfirmed(self):
        highs, lows, closes, volumes = self.make_series()
        prior_high = max(highs[-21:-1])
        closes[-1] = prior_high + 3
        highs[-1] = closes[-1] + 1
        lows[-1] = closes[-1] - 1
        volumes[-1] = 1000
        result = analyze_price_action(highs, lows, closes, volumes)
        self.assertEqual(result["breakout"]["state"], "unconfirmed_bullish")

    def test_result_exposes_invalidation_and_limitations(self):
        highs, lows, closes, volumes = self.make_series()
        result = analyze_price_action(highs, lows, closes, volumes)
        self.assertTrue(result["breakout"]["invalidation_condition"])
        self.assertGreaterEqual(len(result["limitations"]), 3)

    def test_rejects_mismatched_series(self):
        with self.assertRaises(ValueError):
            analyze_price_action([10, 11], [9], [9.5, 10], [100, 200])

    def test_rejects_invalid_ohlc(self):
        with self.assertRaises(ValueError):
            analyze_price_action([10, 11], [9, 10], [11, 10], [100, 200])

    def test_timestamps_must_match_series(self):
        highs, lows, closes, volumes = self.make_series(20)
        with self.assertRaises(ValueError):
            analyze_price_action(highs, lows, closes, volumes, timestamps=["one"])


if __name__ == "__main__":
    unittest.main()
