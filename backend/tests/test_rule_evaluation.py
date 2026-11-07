import unittest

from app.rule_evaluation import compare_rule_versions


class RuleEvaluationTests(unittest.TestCase):
    def make_candles(self, count=90):
        candles = []
        for index in range(count):
            close = 30 + index * 0.1 + ((index % 8) - 4) * 0.2
            candles.append({
                "timestamp": f"2026-01-{(index % 28) + 1:02d}T00:00:00+07:00",
                "open": close - 0.1,
                "high": close + 0.5,
                "low": close - 0.5,
                "close": close,
                "volume": 1000 + index * 10,
                "source": "unit-test-synthetic",
            })
        return candles

    def test_compares_versions_on_identical_input_and_reports_differences(self):
        result = compare_rule_versions(
            self.make_candles(),
            [
                {"version": "1.0.0", "config": {}, "config_sha256": "a" * 64},
                {
                    "version": "1.1.0",
                    "config": {"volume_flow": {"window": 12}},
                    "config_sha256": "b" * 64,
                },
            ],
        )
        self.assertTrue(result["input"]["same_input_for_all_versions"])
        self.assertEqual(result["versions_compared"], ["1.0.0", "1.1.0"])
        self.assertIn("volume_flow_window", result["differences"])
        self.assertEqual(result["results"]["1.0.0"]["volume_flow_window"], 20)
        self.assertEqual(result["results"]["1.1.0"]["volume_flow_window"], 12)
        self.assertIn("backtest", " ".join(result["limitations"]))

    def test_comparison_is_deterministic(self):
        versions = [
            {"version": "1.0.0", "config": {}},
            {"version": "1.1.0", "config": {"fibonacci": {"wing": 1}}},
        ]
        self.assertEqual(
            compare_rule_versions(self.make_candles(), versions),
            compare_rule_versions(self.make_candles(), versions),
        )

    def test_requires_two_to_five_unique_versions(self):
        with self.assertRaises(ValueError):
            compare_rule_versions(self.make_candles(), [{"version": "1.0.0"}])
        with self.assertRaises(ValueError):
            compare_rule_versions(
                self.make_candles(),
                [{"version": "1.0.0"}, {"version": "1.0.0"}],
            )
        with self.assertRaises(ValueError):
            compare_rule_versions(
                self.make_candles(),
                [{"version": str(i)} for i in range(6)],
            )

    def test_rejects_empty_market_data(self):
        with self.assertRaises(ValueError):
            compare_rule_versions([], [{"version": "1.0.0"}, {"version": "1.1.0"}])


if __name__ == "__main__":
    unittest.main()
