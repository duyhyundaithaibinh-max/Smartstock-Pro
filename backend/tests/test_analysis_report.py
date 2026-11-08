import unittest
from unittest.mock import patch

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
            "price_action": {
                "lookback": 60,
                "wing": 3,
                "range_lookback": 30,
                "volume_confirmation_pct": 150,
                "breakout_buffer_atr_pct": 50,
            },
            "fibonacci": {"lookback": 40, "wing": 1},
            "elliott": {"lookback": 60, "wing": 1},
            "volume_flow": {"window": 12},
        }
        with patch(
            "app.analysis_report.fibonacci.analyze_fibonacci",
            return_value={"status": "ok", "method": {"lookback_bars": 40, "pivot_wing": 1}},
        ) as fibonacci_mock:
            result = build_analysis_report(
                self.make_candles(),
                rule_config=config,
                rule_version="2.1.0",
                rule_config_sha256="a" * 64,
            )
        self.assertEqual(result["analysis_rules_version"], "2.1.0")
        self.assertEqual(result["analysis_rule_config_sha256"], "a" * 64)
        self.assertEqual(result["volume_flow"]["window"], 12)
        self.assertEqual(result["trend_and_price_action"]["price_zones"]["lookback_bars"], 60)
        self.assertEqual(result["trend_and_price_action"]["price_zones"]["pivot_wing"], 3)
        self.assertEqual(result["trend_and_price_action"]["breakout"]["range_lookback_bars"], 30)
        self.assertEqual(result["trend_and_price_action"]["breakout"]["volume_confirmation_threshold"], 1.5)
        self.assertEqual(result["trend_and_price_action"]["breakout"]["price_buffer_atr"], 0.5)
        self.assertEqual(fibonacci_mock.call_args.kwargs["lookback"], 40)
        self.assertEqual(fibonacci_mock.call_args.kwargs["wing"], 1)

    def test_report_uses_versioned_indicator_periods(self):
        result = build_analysis_report(
            self.make_candles(120),
            rule_config={"indicators": {
                "ema_fast_period": 10, "ema_slow_period": 30,
                "rsi_period": 9, "macd_fast_period": 8,
                "macd_slow_period": 21, "macd_signal_period": 5,
                "atr_period": 10,
            }},
        )
        self.assertEqual(result["indicators"]["ema_fast_period"], 10)
        self.assertEqual(result["indicators"]["ema_slow_period"], 30)
        trend = result["trend_and_price_action"]["trend"]
        self.assertEqual(trend["ema_fast_period"], 10)
        self.assertEqual(trend["ema_slow_period"], 30)
        self.assertIsNotNone(trend["ema_fast"])
        self.assertIsNotNone(trend["ema_slow"])
        self.assertIsNone(trend["ema20"])
        self.assertIsNone(trend["ema50"])
        self.assertEqual(result["indicators"]["rsi_period"], 9)
        self.assertEqual(result["indicators"]["macd_fast_period"], 8)
        self.assertEqual(result["indicators"]["macd_slow_period"], 21)
        self.assertEqual(result["indicators"]["macd_signal_period"], 5)
        self.assertEqual(result["indicators"]["atr_period"], 10)
        self.assertIsInstance(result["indicators"]["rsi"], float)
        self.assertIsNone(result["indicators"]["rsi14"])


    def test_bearish_evidence_uses_configured_range_lookback(self):
        bearish_trend = {
            "trend": {"classification": "downtrend"},
            "breakout": {"state": "confirmed_bearish", "range_lookback_bars": 30},
            "price_zones": {"supports": [], "resistances": []},
        }
        with patch(
            "app.analysis_report.price_action.analyze_price_action",
            return_value=bearish_trend,
        ):
            result = build_analysis_report(
                self.make_candles(),
                rule_config={"price_action": {"range_lookback": 30}},
            )
        bearish = next(item for item in result["scenarios"] if item["name"] == "bearish")
        self.assertIn("Breakdown thủng biên 30 nến có xác nhận volume", bearish["evidence"])
        self.assertNotIn("Breakdown thủng biên 20 nến có xác nhận volume", bearish["evidence"])



if __name__ == "__main__":
    unittest.main()
