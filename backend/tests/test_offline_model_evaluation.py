import tempfile
from pathlib import Path
from unittest.mock import patch

import pytest

from app import db, knowledge_base, offline_model_evaluation, training_room


@pytest.fixture
def reviewed_example():
    with tempfile.TemporaryDirectory() as directory:
        with patch("app.db.DB_PATH", str(Path(directory) / "evaluation.db")):
            db.init_db()
            knowledge_base.ingest_document(
                "elliott.md",
                ("Sóng 3 không được là sóng ngắn nhất trong cấu trúc đẩy. " * 8).encode(),
                source="internal_curriculum",
                title="Elliott Wave",
            )
            draft = training_room.create_example({
                "question": "Quy tắc nào áp dụng cho sóng 3 Elliott?",
                "expected_answer": "Sóng 3 không được là sóng ngắn nhất trong cấu trúc đẩy.",
                "topic": "elliott",
                "citation_ids": ["kb:1:0"],
            })
            approved = training_room.approve_example(draft["id"])
            yield approved


def test_offline_evaluation_scores_answer_and_citations(reviewed_example):
    result = offline_model_evaluation.evaluate_predictions([{
        "example_id": reviewed_example["id"],
        "answer": reviewed_example["expected_answer"],
        "citation_ids": ["kb:1:0"],
    }])
    assert result["evaluation_type"] == "offline_reference_and_citation_metrics"
    assert result["exact_match_rate"] == 1.0
    assert result["mean_token_f1"] == 1.0
    assert result["mean_citation_precision"] == 1.0
    assert result["mean_citation_recall"] == 1.0
    assert result["invalid_citation_count"] == 0


def test_token_f1_uses_individual_unicode_words():
    scores = offline_model_evaluation._f1(
        "Sóng 3 tăng mạnh",
        "Sóng 3 giảm mạnh",
    )
    assert scores == {
        "token_precision": 0.75,
        "token_recall": 0.75,
        "token_f1": 0.75,
    }


def test_offline_evaluation_flags_missing_and_invalid_citations(reviewed_example):
    result = offline_model_evaluation.evaluate_predictions([{
        "example_id": reviewed_example["id"],
        "answer": "Sóng 3 có quy tắc riêng.",
        "citation_ids": ["kb:999:0"],
    }])
    assert result["invalid_citation_count"] == 1
    assert result["mean_citation_recall"] == 0.0
    assert result["per_example"][0]["missing_gold_citation_count"] == 1


def test_offline_evaluation_rejects_unapproved_examples(reviewed_example):
    with pytest.raises(ValueError, match="unknown or unapproved"):
        offline_model_evaluation.evaluate_predictions([{
            "example_id": reviewed_example["id"] + 1,
            "answer": "A sufficiently long candidate answer.",
            "citation_ids": [],
        }])


def test_offline_evaluation_rejects_boolean_example_id():
    with pytest.raises(ValueError, match="positive integer"):
        offline_model_evaluation.evaluate_predictions([{
            "example_id": True,
            "answer": "A valid-looking answer string.",
            "citation_ids": [],
        }])


def test_offline_evaluation_requires_predictions():
    with pytest.raises(ValueError, match="non-empty"):
        offline_model_evaluation.evaluate_predictions([])
