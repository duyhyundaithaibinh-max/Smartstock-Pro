import unittest

from app.analysis_report import build_analysis_report


class AnalysisReportTests(unittest.TestCase):
    def make_candles(self, count=90):
        candles = []
        for i in range(count):
            close = 20 + i * 0.15
            candles.append({
                "timestamp": f"2026-01-{(i % 28) + 1:02d}T00:00:00+07:00",
                "open": close - 0.1,
                "high": close + 0.5,
                "low": close - 0.5,
                "close": close,
                "volume": 1000 + i * 2,
                "source": "unit-test",
            })
        return candles

    def test_report_contains_all_engines_and_three_scenarios(self):
        result = build_analysis_report(self.make_candles())
        self.assertEqual(result["status"], "ok")
        self.assertIn("trend_and_price_action", result)
        self.assertIn("fibonacci", result)
        self.assertIn("elliott", result)
        self.assertIn("volume_flow", result)
        self.assertEqual([item["name"] for item in result["scenarios"]],
                         ["bullish", "base", "bearish"])
        for scenario in result["scenarios"]:
            self.assertTrue(scenario["confirmation"])
            self.assertTrue(scenario["invalidation"])

    def test_report_preserves_source_and_unknown_adjustment_status(self):
        result = build_analysis_report(self.make_candles())
        self.assertEqual(result["data_quality"]["sources"], ["unit-test"])
        self.assertEqual(result["data_quality"]["price_adjustment"], "unknown")

    def test_empty_candles_rejected(self):
        with self.assertRaises(ValueError):
            build_analysis_report([])

    def test_report_uses_active_rule_configuration_and_version(self):
        config = {
            "fibonacci": {"lookback": 40, "wing": 1},
            "elliott": {"lookback": 60, "wing": 1},
            "volume_flow": {"window": 12},
        }
        result = build_analysis_report(
            self.make_candles(),
            rule_config=config,
            rule_version="2.1.0",
            rule_config_sha256="a" * 64,
        )
        self.assertEqual(result["analysis_rules_version"], "2.1.0")
        self.assertEqual(result["analysis_rule_config_sha256"], "a" * 64)
        self.assertEqual(result["fibonacci"]["method"]["lookback_bars"], 40)
        self.assertEqual(result["fibonacci"]["method"]["pivot_wing"], 1)
        self.assertEqual(result["volume_flow"]["window"], 12)


if __name__ == "__main__":
    unittest.main()
