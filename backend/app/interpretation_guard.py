"""Grounding guard for future AI interpretation of deterministic analysis.

This module does not call a model. It creates an allow-listed evidence packet
and validates structured prose so the UI can render numbers only from engine
facts, never from free-form model text.
"""
from __future__ import annotations

import re
from typing import Any, Mapping


_NUMERIC_TOKEN = re.compile(r"(?<![A-Za-z])[-+]?\d+(?:[.,]\d+)?%?(?![A-Za-z])")


class InterpretationValidationError(ValueError):
    pass


def build_interpretation_context(report: Mapping[str, Any]) -> dict[str, Any]:
    """Return only explicitly approved facts with stable evidence identifiers."""
    if report.get("status") != "ok":
        raise InterpretationValidationError("Only a successful analysis report can be interpreted.")

    facts: dict[str, dict[str, Any]] = {}

    def add(evidence_id: str, value: Any, source_path: str) -> None:
        if value is not None and isinstance(value, (str, int, float, bool)):
            facts[evidence_id] = {"value": value, "source_path": source_path}

    add("report.as_of", report.get("as_of"), "as_of")
    add("report.bars_available", report.get("bars_available"), "bars_available")
    add("market.latest_close", report.get("latest_close"), "latest_close")

    indicators = report.get("indicators") or {}
    for key in ("rsi14", "macd", "macd_signal", "ema20", "ema50", "atr14"):
        add(f"indicator.{key}", indicators.get(key), f"indicators.{key}")

    trend = report.get("trend_and_price_action") or {}
    add(
        "trend.classification",
        (trend.get("trend") or {}).get("classification"),
        "trend_and_price_action.trend.classification",
    )
    add(
        "breakout.state",
        (trend.get("breakout") or {}).get("state"),
        "trend_and_price_action.breakout.state",
    )

    flow = report.get("volume_flow") or {}
    add("volume_flow.classification", flow.get("classification"), "volume_flow.classification")

    for scenario in report.get("scenarios") or []:
        name = scenario.get("name")
        if name not in {"bullish", "base", "bearish"}:
            continue
        add(f"scenario.{name}.status", scenario.get("status"), f"scenarios.{name}.status")
        evidence = scenario.get("evidence") or []
        for index, item in enumerate(evidence):
            if isinstance(item, str):
                add(
                    f"scenario.{name}.evidence.{index}",
                    item,
                    f"scenarios.{name}.evidence[{index}]",
                )

    return {
        "policy": "Narrative only. Every claim must cite one or more evidence_ids. Render quantitative values from facts, never from model prose.",
        "facts": facts,
        "allowed_evidence_ids": sorted(facts),
    }


def validate_interpretation(
    context: Mapping[str, Any],
    proposed: Mapping[str, Any],
) -> dict[str, Any]:
    """Validate a model's structured narrative; never accept free-form numbers."""
    facts = context.get("facts")
    if not isinstance(facts, Mapping):
        raise InterpretationValidationError("Evidence context is invalid.")

    summary = proposed.get("summary")
    claims = proposed.get("claims")
    if not isinstance(summary, str) or not summary.strip():
        raise InterpretationValidationError("A non-empty summary is required.")
    if not isinstance(claims, list) or not claims:
        raise InterpretationValidationError("At least one evidence-backed claim is required.")

    def validate_text(value: Any, label: str) -> str:
        if not isinstance(value, str) or not value.strip():
            raise InterpretationValidationError(f"{label} must be non-empty text.")
        if _NUMERIC_TOKEN.search(value):
            raise InterpretationValidationError(
                f"{label} contains numeric text; quantitative values must be rendered from engine facts."
            )
        return value.strip()

    clean_summary = validate_text(summary, "summary")
    clean_claims = []
    for index, claim in enumerate(claims):
        if not isinstance(claim, Mapping):
            raise InterpretationValidationError(f"claim {index} must be an object.")
        statement = validate_text(claim.get("text"), f"claim {index}")
        evidence_ids = claim.get("evidence_ids")
        if not isinstance(evidence_ids, list) or not evidence_ids:
            raise InterpretationValidationError(f"claim {index} requires evidence_ids.")
        if any(not isinstance(item, str) or item not in facts for item in evidence_ids):
            raise InterpretationValidationError(f"claim {index} cites unknown evidence.")
        if len(set(evidence_ids)) != len(evidence_ids):
            raise InterpretationValidationError(f"claim {index} contains duplicate evidence IDs.")
        clean_claims.append({"text": statement, "evidence_ids": evidence_ids})

    summary_evidence = proposed.get("summary_evidence_ids")
    if not isinstance(summary_evidence, list) or not summary_evidence:
        raise InterpretationValidationError("summary_evidence_ids are required.")
    if any(not isinstance(item, str) or item not in facts for item in summary_evidence):
        raise InterpretationValidationError("Summary cites unknown evidence.")

    return {
        "status": "validated",
        "summary": clean_summary,
        "summary_evidence_ids": summary_evidence,
        "claims": clean_claims,
        "facts": dict(facts),
        "policy": "AI narrative validated; all quantitative facts remain sourced from deterministic engine output.",
    }
