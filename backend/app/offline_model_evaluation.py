"""Offline evaluation of candidate local-model answers against reviewed examples.

This module does not invoke or train a model. It scores predictions supplied by
a locally run model, using reviewed answers and source-citation metadata.
"""
from __future__ import annotations

import re
from collections import Counter
from typing import Any

from .db import connection
from .training_room import _citation_exists


_TOKEN = re.compile(r"[^\\W_]+", re.UNICODE)


def _tokens(value: str) -> Counter[str]:
    return Counter(_TOKEN.findall(" ".join(value.casefold().split())))


def _f1(reference: str, candidate: str) -> dict[str, float]:
    expected = _tokens(reference)
    actual = _tokens(candidate)
    overlap = sum((expected & actual).values())
    precision = overlap / sum(actual.values()) if actual else 0.0
    recall = overlap / sum(expected.values()) if expected else 0.0
    score = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    return {"token_precision": round(precision, 4),
            "token_recall": round(recall, 4), "token_f1": round(score, 4)}


def evaluate_predictions(predictions: Any) -> dict[str, Any]:
    """Score predictions shaped as {example_id, answer, citation_ids}."""
    if not isinstance(predictions, list) or not predictions:
        raise ValueError("Provide a non-empty predictions list.")
    if len(predictions) > 500:
        raise ValueError("At most 500 predictions may be evaluated.")

    normalized: dict[int, dict[str, Any]] = {}
    for item in predictions:
        if not isinstance(item, dict):
            raise ValueError("Each prediction must be an object.")
        example_id = item.get("example_id")
        answer = item.get("answer")
        citations = item.get("citation_ids", [])
        if not isinstance(example_id, int) or example_id < 1:
            raise ValueError("example_id must be a positive integer.")
        if example_id in normalized:
            raise ValueError(f"Duplicate prediction for example_id={example_id}.")
        if not isinstance(answer, str) or not answer.strip() or len(answer) > 10000:
            raise ValueError("answer must contain 1 to 10000 characters.")
        if not isinstance(citations, list) or any(
            not isinstance(value, str) or len(value) > 80 for value in citations
        ):
            raise ValueError("citation_ids must be a list of citation strings.")
        normalized[example_id] = {
            "answer": answer.strip(),
            "citation_ids": sorted(set(citations)),
        }

    with connection() as conn:
        approved = {
            row["id"]: dict(row)
            for row in conn.execute(
                "SELECT * FROM training_examples WHERE status='approved'"
            ).fetchall()
        }
        if not approved:
            raise ValueError("No approved reference examples are available.")
        unknown = sorted(set(normalized) - set(approved))
        if unknown:
            raise ValueError(f"Predictions reference unknown or unapproved examples: {unknown}")
        rows = []
        for example_id, prediction in normalized.items():
            reference = approved[example_id]
            gold_citations = set(__import__("json").loads(reference["citation_ids"]))
            predicted_citations = set(prediction["citation_ids"])
            valid_predicted = {
                citation for citation in predicted_citations
                if _citation_exists(conn, citation)
            }
            overlap = gold_citations & predicted_citations
            citation_precision = len(overlap) / len(predicted_citations) if predicted_citations else 0.0
            citation_recall = len(overlap) / len(gold_citations) if gold_citations else 0.0
            rows.append({
                "example_id": example_id,
                "topic": reference["topic"],
                "exact_match": " ".join(prediction["answer"].casefold().split())
                               == " ".join(reference["expected_answer"].casefold().split()),
                **_f1(reference["expected_answer"], prediction["answer"]),
                "citation_precision": round(citation_precision, 4),
                "citation_recall": round(citation_recall, 4),
                "invalid_citation_count": len(predicted_citations - valid_predicted),
                "missing_gold_citation_count": len(gold_citations - predicted_citations),
            })

    count = len(rows)
    return {
        "evaluation_type": "offline_reference_and_citation_metrics",
        "predictions_evaluated": count,
        "approved_reference_examples": len(approved),
        "coverage": round(count / len(approved), 4),
        "exact_match_rate": round(sum(row["exact_match"] for row in rows) / count, 4),
        "mean_token_f1": round(sum(row["token_f1"] for row in rows) / count, 4),
        "mean_citation_precision": round(sum(row["citation_precision"] for row in rows) / count, 4),
        "mean_citation_recall": round(sum(row["citation_recall"] for row in rows) / count, 4),
        "invalid_citation_count": sum(row["invalid_citation_count"] for row in rows),
        "per_example": rows,
        "limitations": [
            "Token overlap and exact match do not measure semantic correctness.",
            "A valid citation ID does not prove that the cited passage supports the answer.",
            "Use a held-out test set and human review before relying on model outputs.",
            "This evaluator does not load, train, fine-tune, or call any model.",
        ],
    }
