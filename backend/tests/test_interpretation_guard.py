import pytest

from app.interpretation_guard import (
    InterpretationValidationError,
    build_interpretation_context,
    validate_interpretation,
)


@pytest.fixture
def report():
    return {
        "status": "ok",
        "as_of": "2026-11-06T00:00:00+07:00",
        "bars_available": 120,
        "latest_close": 42.5,
        "indicators": {
            "rsi": 61.2, "rsi_period": 9, "macd": 0.8, "macd_signal": 0.4,
            "ema_fast": 41.7, "ema_fast_period": 10, "ema_slow": 39.9,
            "ema_slow_period": 30, "atr": 1.1, "atr_period": 10,
        },
        "trend_and_price_action": {"trend": {"classification": "uptrend"}, "breakout": {"state": "inside_range"}},
        "volume_flow": {"classification": "accumulation_candidate"},
        "scenarios": [
            {"name": "bullish", "status": "supported", "evidence": ["Xu hướng đang nghiêng tăng"]},
            {"name": "base", "status": "active", "evidence": []},
            {"name": "bearish", "status": "conditional", "evidence": []},
        ],
    }


def valid_proposal():
    return {
        "summary": "Cấu trúc hiện tại nghiêng về kịch bản tích cực nhưng vẫn cần chờ xác nhận.",
        "summary_evidence_ids": ["trend.classification", "volume_flow.classification"],
        "claims": [
            {
                "text": "Xu hướng và dòng tiền đang cung cấp tín hiệu hỗ trợ cho kịch bản tăng.",
                "evidence_ids": ["trend.classification", "volume_flow.classification"],
            }
        ],
    }


def test_context_contains_allowlisted_engine_facts_only(report):
    context = build_interpretation_context(report)
    assert context["facts"]["market.latest_close"]["value"] == 42.5
    assert context["facts"]["indicator.rsi"]["value"] == 61.2
    assert context["facts"]["indicator.rsi_period"]["value"] == 9
    assert "latest_close" not in context["facts"]


def test_valid_grounded_interpretation_is_accepted(report):
    context = build_interpretation_context(report)
    result = validate_interpretation(context, valid_proposal())
    assert result["status"] == "validated"
    assert result["facts"]["market.latest_close"]["value"] == 42.5


def test_model_cannot_invent_numeric_values_in_summary(report):
    context = build_interpretation_context(report)
    proposal = valid_proposal()
    proposal["summary"] = "Giá sẽ tăng 15% trong tuần tới."
    with pytest.raises(InterpretationValidationError, match="numeric text"):
        validate_interpretation(context, proposal)


def test_every_claim_requires_known_evidence(report):
    context = build_interpretation_context(report)
    proposal = valid_proposal()
    proposal["claims"][0]["evidence_ids"] = ["invented.price_target"]
    with pytest.raises(InterpretationValidationError, match="unknown evidence"):
        validate_interpretation(context, proposal)


def test_claim_without_evidence_is_rejected(report):
    context = build_interpretation_context(report)
    proposal = valid_proposal()
    proposal["claims"][0]["evidence_ids"] = []
    with pytest.raises(InterpretationValidationError, match="requires evidence_ids"):
        validate_interpretation(context, proposal)


def test_summary_without_evidence_is_rejected(report):
    context = build_interpretation_context(report)
    proposal = valid_proposal()
    proposal["summary_evidence_ids"] = []
    with pytest.raises(InterpretationValidationError, match="summary_evidence_ids"):
        validate_interpretation(context, proposal)


def test_non_success_report_cannot_be_interpreted():
    with pytest.raises(InterpretationValidationError, match="successful"):
        build_interpretation_context({"status": "insufficient_data"})


def test_unknown_scenario_names_are_not_exposed(report):
    report["scenarios"].append({"name": "unexpected", "status": "active", "evidence": ["x"]})
    context = build_interpretation_context(report)
    assert not any(key.startswith("scenario.unexpected") for key in context["facts"])
