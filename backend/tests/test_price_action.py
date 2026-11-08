import unittest

from app.price_action import analyze_price_action, _cluster_levels


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

    def test_configurable_range_and_volume_thresholds_are_reported(self):
        highs, lows, closes, volumes = self.make_series()
        result = analyze_price_action(
            highs, lows, closes, volumes,
            range_lookback=30,
            volume_confirmation_pct=150,
            breakout_buffer_atr_pct=50,
            lookback=60,
            wing=3,
        )
        self.assertEqual(result["breakout"]["range_lookback_bars"], 30)
        self.assertEqual(result["breakout"]["volume_confirmation_threshold"], 1.5)
        self.assertEqual(result["breakout"]["price_buffer_atr"], 0.5)
        self.assertEqual(result["price_zones"]["lookback_bars"], 60)
        self.assertEqual(result["price_zones"]["pivot_wing"], 3)
        self.assertIn("1.50 lần trung bình 30 nến", result["breakout"]["confirmation_condition"])

    def test_rule_parameters_are_range_validated(self):
        highs, lows, closes, volumes = self.make_series()
        for kwargs in (
            {"range_lookback": 19},
            {"volume_confirmation_pct": 99},
            {"breakout_buffer_atr_pct": 201},
            {"wing": 0},
        ):
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                analyze_price_action(highs, lows, closes, volumes, **kwargs)

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

    def test_pivot_level_recency_counts_bars_to_latest_candle(self):
        levels = _cluster_levels([(2, 10.0), (5, 10.2)], 0.5, total_bars=8)
        self.assertEqual(len(levels), 1)
        self.assertEqual(levels[0]["touches"], 2)
        self.assertEqual(levels[0]["last_seen_bars_ago"], 2)

    def test_timestamps_must_match_series(self):
        highs, lows, closes, volumes = self.make_series(20)
        with self.assertRaises(ValueError):
            analyze_price_action(highs, lows, closes, volumes, timestamps=["one"])


if __name__ == "__main__":
    unittest.main()
