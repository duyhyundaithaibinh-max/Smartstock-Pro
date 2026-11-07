"""Golden/regression quality checks for the deterministic analysis engine.

Synthetic candles in this module are test fixtures only; they are never market data.
"""
import math
from datetime import datetime, timedelta

import pytest

from app.analysis_report import build_analysis_report
from app.interpretation_guard import build_interpretation_context


@pytest.fixture
def synthetic_candles():
    candles = []
    for index in range(120):
        close = 30.0 + index * 0.12 + math.sin(index / 4.0) * 1.8
        candles.append({
            "timestamp": (datetime(2026, 1, 1) + timedelta(days=index)).isoformat() + "+07:00",
            "open": round(close - 0.25, 4),
            "high": round(close + 0.8, 4),
            "low": round(close - 0.8, 4),
            "close": round(close, 4),
            "volume": float(100_000 + (index % 9) * 5_000),
            "source": "unit-test-synthetic",
        })
    return candles


def test_golden_report_has_stable_contract_and_rule_version(synthetic_candles):
    first = build_analysis_report(synthetic_candles)
    second = build_analysis_report(synthetic_candles)

    assert first == second
    assert first["analysis_rules_version"] == "1.0.0"
    assert first["status"] == "ok"
    assert first["bars_available"] == 120
    assert first["as_of"] == synthetic_candles[-1]["timestamp"]
    assert first["latest_close"] == synthetic_candles[-1]["close"]
    assert first["data_quality"]["sources"] == ["unit-test-synthetic"]
    assert first["data_quality"]["price_adjustment"] == "unknown"


def test_report_scenarios_have_fixed_order_and_required_fields(synthetic_candles):
    report = build_analysis_report(synthetic_candles)
    scenarios = report["scenarios"]

    assert [item["name"] for item in scenarios] == ["bullish", "base", "bearish"]
    for item in scenarios:
        assert item["status"] in {"supported", "conditional", "active"}
        assert isinstance(item["evidence"], list)
        assert isinstance(item["confirmation"], str) and item["confirmation"]
        assert isinstance(item["invalidation"], str) and item["invalidation"]


def test_interpretation_packet_matches_engine_facts_exactly(synthetic_candles):
    report = build_analysis_report(synthetic_candles)
    context = build_interpretation_context(report)
    facts = context["facts"]

    assert facts["report.rules_version"]["value"] == report["analysis_rules_version"]
    assert facts["report.as_of"]["value"] == report["as_of"]
    assert facts["report.bars_available"]["value"] == report["bars_available"]
    assert facts["market.latest_close"]["value"] == report["latest_close"]
    for key in ("rsi14", "macd", "macd_signal", "ema20", "ema50", "atr14"):
        fact = facts.get(f"indicator.{key}")
        expected = report["indicators"][key]
        if expected is None:
            assert fact is None
        else:
            assert fact["value"] == expected
    assert facts["data.price_adjustment"]["value"] == "unknown"
    assert facts["data.source.0"]["value"] == "unit-test-synthetic"
    assert facts["data.source.0"]["source_path"] == "data_quality.sources[0]"
    assert set(context["allowed_evidence_ids"]) == set(facts)


def test_report_handles_short_history_without_fabricating_bars(synthetic_candles):
    report = build_analysis_report(synthetic_candles[:8])

    assert report["status"] == "ok"
    assert report["bars_available"] == 8
    assert report["latest_close"] == synthetic_candles[7]["close"]
    assert report["indicators"]["ema50"] is None
    assert report["data_quality"]["sources"] == ["unit-test-synthetic"]


def test_empty_history_is_rejected():
    with pytest.raises(ValueError, match="At least one candle"):
        build_analysis_report([])


def test_missing_indicator_and_provenance_are_not_fabricated(synthetic_candles):
    report = build_analysis_report(synthetic_candles[:8])
    context = build_interpretation_context(report)
    facts = context["facts"]

    assert "indicator.ema50" not in facts
    assert "indicator.rsi14" not in facts
    assert facts["report.bars_available"]["value"] == 8
    assert facts["data.price_adjustment"]["value"] == "unknown"
    assert facts["data.source.0"]["value"] == "unit-test-synthetic"


def test_multiple_sources_are_preserved_as_distinct_evidence(synthetic_candles):
    candles = [dict(item) for item in synthetic_candles]
    candles[0]["source"] = "provider-a"
    candles[-1]["source"] = "provider-b"
    report = build_analysis_report(candles)
    context = build_interpretation_context(report)

    assert report["data_quality"]["sources"] == ["provider-a", "provider-b"]
    assert context["facts"]["data.source.0"]["value"] == "provider-a"
    assert context["facts"]["data.source.1"]["value"] == "provider-b"
