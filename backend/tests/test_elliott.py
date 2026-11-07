import unittest

from app.elliott import _evaluate_impulse, analyze_elliott


class ElliottTests(unittest.TestCase):
    def test_valid_bullish_impulse_candidate(self):
        pivots = [
            (2, "low", 10.0), (5, "high", 15.0), (8, "low", 12.0),
            (11, "high", 22.0), (14, "low", 17.0), (17, "high", 25.0),
        ]
        result = _evaluate_impulse(pivots)
        self.assertEqual(result["direction"], "bullish")
        self.assertEqual(result["status"], "structurally_valid_candidate")
        self.assertEqual(result["rule_score"], 100)

    def test_wave_four_overlap_invalidates_standard_impulse(self):
        pivots = [
            (2, "low", 10.0), (5, "high", 15.0), (8, "low", 12.0),
            (11, "high", 22.0), (14, "low", 14.0), (17, "high", 25.0),
        ]
        result = _evaluate_impulse(pivots)
        self.assertEqual(result["status"], "invalidated_candidate")
        self.assertFalse(next(x for x in result["rule_checks"] if x["rule"] == "wave_4_does_not_overlap_wave_1")["passed"])

    def test_valid_bearish_impulse_candidate(self):
        pivots = [
            (2, "high", 25.0), (5, "low", 20.0), (8, "high", 23.0),
            (11, "low", 13.0), (14, "high", 18.0), (17, "low", 10.0),
        ]
        result = _evaluate_impulse(pivots)
        self.assertEqual(result["direction"], "bearish")
        self.assertEqual(result["status"], "structurally_valid_candidate")

    def test_insufficient_confirmed_pivots_is_not_forced_into_a_count(self):
        closes = [float(value) for value in range(20, 50)]
        highs = [value + 1 for value in closes]
        lows = [value - 1 for value in closes]
        result = analyze_elliott(highs, lows, closes)
        self.assertEqual(result["status"], "incomplete")
        self.assertEqual(result["required_pivots"], 6)

    def test_rejects_invalid_series_and_timestamp_length(self):
        with self.assertRaises(ValueError):
            analyze_elliott([10, 11], [9, 10], [11, 10])
        with self.assertRaises(ValueError):
            analyze_elliott([10, 11], [9, 10], [9.5, 10], ["only-one"])


if __name__ == "__main__":
    unittest.main()
