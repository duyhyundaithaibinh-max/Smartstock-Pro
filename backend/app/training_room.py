"""Human-reviewed training examples for the local SmartStock AI Training Room.

This stores supervised examples and evaluates dataset readiness. It does not
fine-tune or call a model; approved examples are exported for a later local
training/evaluation pipeline.
"""
from __future__ import annotations

import json
import re
from collections import Counter
from typing import Any

from .db import connection

_CITATION = re.compile(r"^kb:(\d+):(\d+)$")


class TrainingDataError(ValueError):
    """A user-correctable training-data validation error."""


def _clean_text(value: Any, label: str, minimum: int, maximum: int) -> str:
    if not isinstance(value, str):
        raise TrainingDataError(f"{label} must be text.")
    result = value.strip()
    if not minimum <= len(result) <= maximum:
        raise TrainingDataError(f"{label} must contain {minimum} to {maximum} characters.")
    return result


def _validate_citations(citations: Any) -> list[str]:
    if not isinstance(citations, list) or not 1 <= len(citations) <= 10:
        raise TrainingDataError("Provide 1 to 10 source citation IDs.")
    clean: list[str] = []
    for citation in citations:
        if not isinstance(citation, str) or not _CITATION.fullmatch(citation):
            raise TrainingDataError("Citation IDs must use the kb:document_id:chunk_index format.")
        if citation in clean:
            raise TrainingDataError("Duplicate citation IDs are not allowed.")
        match = _CITATION.fullmatch(citation)
        assert match is not None
        document_id, chunk_index = int(match.group(1)), int(match.group(2))
        with connection() as conn:
            exists = conn.execute(
                """SELECT 1 FROM knowledge_chunks
                   WHERE document_id=? AND chunk_index=?""",
                (document_id, chunk_index),
            ).fetchone()
        if not exists:
            raise TrainingDataError(f"Source citation does not exist: {citation}")
        clean.append(citation)
    return clean


def create_example(payload: dict[str, Any]) -> dict[str, Any]:
    question = _clean_text(payload.get("question"), "Question", 10, 1000)
    answer = _clean_text(payload.get("expected_answer"), "Expected answer", 20, 5000)
    topic = _clean_text(payload.get("topic", "general"), "Topic", 1, 80)
    citations = _validate_citations(payload.get("citation_ids"))
    with connection() as conn:
        cursor = conn.execute(
            """INSERT INTO training_examples
               (question,expected_answer,topic,citation_ids,status)
               VALUES(?,?,?,?,'draft')""",
            (question, answer, topic, json.dumps(citations, ensure_ascii=False)),
        )
        row = conn.execute(
            "SELECT * FROM training_examples WHERE id=?", (cursor.lastrowid,)
        ).fetchone()
    return _serialize(row)


def _serialize(row: Any) -> dict[str, Any]:
    item = dict(row)
    item["citation_ids"] = json.loads(item["citation_ids"])
    return item


def list_examples(limit: int = 100, offset: int = 0, status: str | None = None) -> dict[str, Any]:
    if status not in (None, "draft", "approved"):
        raise TrainingDataError("Status must be draft or approved.")
    where = " WHERE status=?" if status else ""
    params: list[Any] = [status] if status else []
    with connection() as conn:
        total = conn.execute("SELECT COUNT(*) FROM training_examples" + where, params).fetchone()[0]
        rows = conn.execute(
            "SELECT * FROM training_examples" + where +
            " ORDER BY created_at DESC,id DESC LIMIT ? OFFSET ?",
            [*params, limit, offset],
        ).fetchall()
    return {"total": total, "limit": limit, "offset": offset,
            "items": [_serialize(row) for row in rows]}


def approve_example(example_id: int) -> dict[str, Any] | None:
    with connection() as conn:
        row = conn.execute(
            "SELECT * FROM training_examples WHERE id=?", (example_id,)
        ).fetchone()
        if row is None:
            return None
        citations = json.loads(row["citation_ids"])
        for citation in citations:
            match = _CITATION.fullmatch(citation)
            if match is None:
                raise TrainingDataError("Stored citation format is invalid.")
            exists = conn.execute(
                """SELECT 1 FROM knowledge_chunks
                   WHERE document_id=? AND chunk_index=?""",
                (int(match.group(1)), int(match.group(2))),
            ).fetchone()
            if not exists:
                raise TrainingDataError(f"Source was deleted; cannot approve: {citation}")
        conn.execute(
            "UPDATE training_examples SET status='approved',updated_at=CURRENT_TIMESTAMP WHERE id=?",
            (example_id,),
        )
        updated = conn.execute(
            "SELECT * FROM training_examples WHERE id=?", (example_id,)
        ).fetchone()
    return _serialize(updated)


def delete_example(example_id: int) -> bool:
    with connection() as conn:
        cursor = conn.execute("DELETE FROM training_examples WHERE id=?", (example_id,))
        return cursor.rowcount > 0


def evaluate_dataset() -> dict[str, Any]:
    with connection() as conn:
        rows = conn.execute("SELECT * FROM training_examples ORDER BY id").fetchall()
        source_count = conn.execute("SELECT COUNT(*) FROM knowledge_documents").fetchone()[0]
    normalized_questions = [
        " ".join(str(row["question"]).casefold().split()) for row in rows
    ]
    duplicate_counts = Counter(normalized_questions)
    duplicates = sorted(question for question, count in duplicate_counts.items() if count > 1)
    topics = Counter(row["topic"] for row in rows)
    approved = sum(row["status"] == "approved" for row in rows)
    draft = len(rows) - approved
    return {
        "total_examples": len(rows),
        "approved_examples": approved,
        "draft_examples": draft,
        "source_documents": source_count,
        "duplicate_question_groups": len(duplicates),
        "topics": dict(sorted(topics.items())),
        "readiness": "ready_for_local_model_evaluation" if approved >= 10 and not duplicates
                     else "collect_and_review_more_examples",
        "minimum_approved_examples_for_initial_evaluation": 10,
        "notes": [
            "Approval is a human review step, not a claim that an answer is objectively correct.",
            "Examples are not used to train a model automatically.",
            "No external model/API is called and no paid service is required.",
        ],
    }


def export_approved_jsonl() -> dict[str, Any]:
    with connection() as conn:
        rows = conn.execute(
            "SELECT * FROM training_examples WHERE status='approved' ORDER BY id"
        ).fetchall()
    lines = []
    for row in rows:
        item = _serialize(row)
        lines.append(json.dumps({
            "messages": [
                {"role": "user", "content": item["question"]},
                {"role": "assistant", "content": item["expected_answer"]},
            ],
            "metadata": {
                "topic": item["topic"],
                "citation_ids": item["citation_ids"],
                "example_id": item["id"],
            },
        }, ensure_ascii=False, separators=(",", ":")))
    return {"format": "jsonl", "count": len(lines), "content": "\n".join(lines)}
