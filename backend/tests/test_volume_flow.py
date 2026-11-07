import unittest

from app.volume_flow import analyze_volume_flow


class VolumeFlowTests(unittest.TestCase):
    def make_series(self, count=40, rising=True):
        closes = [100.0 + i if rising else 140.0 - i for i in range(count)]
        highs = [value + 2 for value in closes]
        lows = [value - 2 for value in closes]
        volumes = [1000.0] * count
        return highs, lows, closes, volumes

    def test_rising_close_near_high_is_accumulation_candidate(self):
        highs, lows, closes, volumes = self.make_series()
        # Close near each candle high gives positive Chaikin money flow.
        lows = [value - 4 for value in closes]
        highs = [value + 1 for value in closes]
        result = analyze_volume_flow(highs, lows, closes, volumes)
        self.assertEqual(result["classification"], "accumulation_candidate")
        self.assertGreater(result["money_flow"]["chaikin_money_flow"], 0.05)

    def test_falling_close_near_low_is_distribution_candidate(self):
        highs, lows, closes, volumes = self.make_series(rising=False)
        highs = [value + 4 for value in closes]
        lows = [value - 1 for value in closes]
        result = analyze_volume_flow(highs, lows, closes, volumes)
        self.assertEqual(result["classification"], "distribution_candidate")
        self.assertLess(result["money_flow"]["chaikin_money_flow"], -0.05)

    def test_volume_contraction_is_measured_against_prior_window(self):
        highs, lows, closes, volumes = self.make_series()
        volumes[-10:] = [500.0] * 10
        result = analyze_volume_flow(highs, lows, closes, volumes)
        self.assertTrue(result["volume_behavior"]["contraction"])

    def test_insufficient_data_and_invalid_inputs(self):
        result = analyze_volume_flow([11] * 5, [9] * 5, [10] * 5, [100] * 5)
        self.assertEqual(result["status"], "insufficient_data")
        with self.assertRaises(ValueError):
            analyze_volume_flow([10, 11], [9, 10], [11, 10], [100, 200])
        with self.assertRaises(ValueError):
            analyze_volume_flow([10, 11], [9, 10], [9.5, 10], [100, 200], timestamps=["one"])


if __name__ == "__main__":
    unittest.main()
