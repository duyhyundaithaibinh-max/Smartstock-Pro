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


class TrainingConflictError(TrainingDataError):
    """A state transition or revision conflict."""


def _clean_text(value: Any, label: str, minimum: int, maximum: int) -> str:
    if not isinstance(value, str):
        raise TrainingDataError(f"{label} must be text.")
    result = value.strip()
    if not minimum <= len(result) <= maximum:
        raise TrainingDataError(f"{label} must contain {minimum} to {maximum} characters.")
    return result


def _citation_exists(conn: Any, citation: str) -> bool:
    match = _CITATION.fullmatch(citation)
    if match is None:
        return False
    return conn.execute(
        """SELECT 1 FROM knowledge_chunks WHERE document_id=? AND chunk_index=?""",
        (int(match.group(1)), int(match.group(2))),
    ).fetchone() is not None


def _validate_citations(conn: Any, citations: Any) -> list[str]:
    """Validate every citation using the caller's transaction/connection."""
    if not isinstance(citations, list) or not 1 <= len(citations) <= 10:
        raise TrainingDataError("Provide 1 to 10 source citation IDs.")
    clean: list[str] = []
    for citation in citations:
        if not isinstance(citation, str) or not _CITATION.fullmatch(citation):
            raise TrainingDataError("Citation IDs must use the kb:document_id:chunk_index format.")
        if citation in clean:
            raise TrainingDataError("Duplicate citation IDs are not allowed.")
        if not _citation_exists(conn, citation):
            raise TrainingDataError(f"Source citation does not exist: {citation}")
        clean.append(citation)
    return clean


def create_example(payload: dict[str, Any]) -> dict[str, Any]:
    question = _clean_text(payload.get("question"), "Question", 10, 1000)
    answer = _clean_text(payload.get("expected_answer"), "Expected answer", 20, 5000)
    topic = _clean_text(payload.get("topic", "general"), "Topic", 1, 80)
    with connection() as conn:
        # Acquire the SQLite write reservation before reading citations so a
        # concurrent document deletion cannot slip between validation and insert.
        conn.execute("BEGIN IMMEDIATE")
        citations = _validate_citations(conn, payload.get("citation_ids"))
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
    if status not in (None, "draft", "approved", "rejected"):
        raise TrainingDataError("Status must be draft, approved or rejected.")
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
        # Reserve the SQLite write lock before reading the example or its
        # citations. This serializes approval with concurrent source deletion.
        conn.execute("BEGIN IMMEDIATE")
        row = conn.execute(
            "SELECT * FROM training_examples WHERE id=?", (example_id,)
        ).fetchone()
        if row is None:
            return None
        if row["status"] != "draft":
            raise TrainingConflictError("Only draft examples can be approved.")
        citations = json.loads(row["citation_ids"])
        for citation in citations:
            if not _citation_exists(conn, citation):
                raise TrainingDataError(f"Source is missing or invalid; cannot approve: {citation}")
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
        # Keep example counts and source validation on one consistent snapshot.
        conn.execute("BEGIN")
        rows = conn.execute("SELECT * FROM training_examples ORDER BY id").fetchall()
        source_count = conn.execute("SELECT COUNT(*) FROM knowledge_documents").fetchone()[0]
        invalid_approved = sum(
            row["status"] == "approved" and not all(
                _citation_exists(conn, citation) for citation in json.loads(row["citation_ids"])
            )
            for row in rows
        )
    active_rows = [row for row in rows if row["status"] != "rejected"]
    normalized_questions = [
        " ".join(str(row["question"]).casefold().split()) for row in active_rows
    ]
    duplicate_counts = Counter(normalized_questions)
    duplicates = sorted(question for question, count in duplicate_counts.items() if count > 1)
    topics = Counter(row["topic"] for row in active_rows)
    approved = sum(row["status"] == "approved" for row in rows)
    rejected = sum(row["status"] == "rejected" for row in rows)
    valid_approved = approved - invalid_approved
    draft = sum(row["status"] == "draft" for row in rows)
    return {
        "total_examples": len(rows),
        "approved_examples": approved,
        "valid_approved_examples": valid_approved,
        "draft_examples": draft,
        "rejected_examples": rejected,
        "approved_examples_with_missing_sources": invalid_approved,
        "source_documents": source_count,
        "duplicate_question_groups": len(duplicates),
        "topics": dict(sorted(topics.items())),
        "readiness": "ready_for_local_model_evaluation"
                     if valid_approved >= 10 and not duplicates and not invalid_approved
                     else "collect_and_review_more_examples",
        "minimum_approved_examples_for_initial_evaluation": 10,
        "notes": [
            "Approval is a human review step, not a claim that an answer is objectively correct.",
            "Examples with deleted source chunks are excluded from export.",
            "Examples are not used to train a model automatically.",
            "No external model/API is called and no paid service is required.",
        ],
    }

def export_approved_jsonl() -> dict[str, Any]:
    with connection() as conn:
        # Export content and citation checks must observe the same DB snapshot.
        conn.execute("BEGIN")
        rows = conn.execute(
            "SELECT * FROM training_examples WHERE status='approved' ORDER BY id"
        ).fetchall()
        rows = [
            row for row in rows
            if all(_citation_exists(conn, citation) for citation in json.loads(row["citation_ids"]))
        ]
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


def _owner_id(reviewer_user_id: Any) -> int:
    if type(reviewer_user_id) is not int or reviewer_user_id <= 0:
        raise TrainingDataError("An authenticated owner account is required for review.")
    return reviewer_user_id


def reject_example(example_id: int, reason: Any, reviewer_user_id: int) -> dict[str, Any] | None:
    clean_reason = _clean_text(reason, "Rejection reason", 1, 1000)
    reviewer_id = _owner_id(reviewer_user_id)
    with connection() as conn:
        conn.execute("BEGIN IMMEDIATE")
        row = conn.execute("SELECT * FROM training_examples WHERE id=?", (example_id,)).fetchone()
        if row is None:
            return None
        if row["status"] != "draft":
            raise TrainingConflictError("Only draft examples can be rejected.")
        conn.execute(
            "UPDATE training_examples SET status='rejected',updated_at=CURRENT_TIMESTAMP WHERE id=? AND status='draft'",
            (example_id,),
        )
        conn.execute("""
            INSERT INTO training_example_review_events
                (example_id,action,reason,revision_from,revision_to,changed_fields,reviewer_user_id)
            VALUES(?,'rejected',?,?,?,'[]',?)
        """, (example_id, clean_reason, row["revision"], row["revision"], reviewer_id))
        updated = conn.execute("SELECT * FROM training_examples WHERE id=?", (example_id,)).fetchone()
    return _serialize(updated)


def edit_draft_example(example_id: int, payload: dict[str, Any], reviewer_user_id: int) -> dict[str, Any] | None:
    reviewer_id = _owner_id(reviewer_user_id)
    if not isinstance(payload, dict):
        raise TrainingDataError("Edit payload must be an object.")
    allowed = {"question", "expected_answer", "topic", "citation_ids", "expected_revision"}
    if set(payload) - allowed:
        raise TrainingDataError("Edit contains unsupported fields.")
    expected_revision = payload.get("expected_revision")
    if type(expected_revision) is not int or expected_revision < 1:
        raise TrainingDataError("expected_revision must be a positive integer.")
    changed = set(payload) - {"expected_revision"}
    if not changed:
        raise TrainingDataError("Provide at least one field to update.")
    with connection() as conn:
        conn.execute("BEGIN IMMEDIATE")
        row = conn.execute("SELECT * FROM training_examples WHERE id=?", (example_id,)).fetchone()
        if row is None:
            return None
        if row["status"] != "draft":
            raise TrainingConflictError("Only draft examples can be edited.")
        if row["revision"] != expected_revision:
            raise TrainingConflictError("The example revision is stale; reload before editing.")
        current = {
            "question": row["question"],
            "expected_answer": row["expected_answer"],
            "topic": row["topic"],
            "citation_ids": json.loads(row["citation_ids"]),
        }
        current.update({key: payload[key] for key in changed})
        question = _clean_text(current["question"], "Question", 10, 1000)
        answer = _clean_text(current["expected_answer"], "Expected answer", 20, 5000)
        topic = _clean_text(current["topic"], "Topic", 1, 80)
        citations = _validate_citations(conn, current["citation_ids"])
        next_revision = row["revision"] + 1
        cursor = conn.execute("""
            UPDATE training_examples
            SET question=?,expected_answer=?,topic=?,citation_ids=?,revision=?,updated_at=CURRENT_TIMESTAMP
            WHERE id=? AND status='draft' AND revision=?
        """, (question, answer, topic, json.dumps(citations, ensure_ascii=False),
              next_revision, example_id, expected_revision))
        if cursor.rowcount != 1:
            raise TrainingConflictError("The example revision changed; reload before editing.")
        conn.execute("""
            INSERT INTO training_example_review_events
                (example_id,action,reason,revision_from,revision_to,changed_fields,reviewer_user_id)
            VALUES(?,'edited',NULL,?,?,?,?)
        """, (example_id, expected_revision, next_revision,
              json.dumps(sorted(changed)), reviewer_id))
        updated = conn.execute("SELECT * FROM training_examples WHERE id=?", (example_id,)).fetchone()
    return _serialize(updated)


_SUPPORTED_QUALITY_RUBRICS = {"qa-quality-v1"}


def create_quality_review(example_id: int, score: Any, rubric_version: Any,
                          rationale: Any, reviewer_user_id: int) -> dict[str, Any] | None:
    reviewer_id = _owner_id(reviewer_user_id)
    if type(score) is not int or not 0 <= score <= 100:
        raise TrainingDataError("Quality score must be an integer from 0 to 100.")
    rubric = _clean_text(rubric_version, "Rubric version", 1, 40)
    if rubric not in _SUPPORTED_QUALITY_RUBRICS:
        raise TrainingDataError("Unsupported quality rubric version.")
    clean_rationale = _clean_text(rationale, "Rationale", 10, 2000)
    with connection() as conn:
        conn.execute("BEGIN IMMEDIATE")
        row = conn.execute("SELECT * FROM training_examples WHERE id=?", (example_id,)).fetchone()
        if row is None:
            return None
        cursor = conn.execute("""
            INSERT INTO training_example_quality_reviews
                (example_id,example_revision,score,rubric_version,rationale,reviewer_user_id)
            VALUES(?,?,?,?,?,?)
        """, (example_id, row["revision"], score, rubric, clean_rationale, reviewer_id))
        review = conn.execute(
            "SELECT * FROM training_example_quality_reviews WHERE id=?", (cursor.lastrowid,)
        ).fetchone()
    return dict(review)


def list_quality_reviews(example_id: int) -> list[dict[str, Any]] | None:
    with connection() as conn:
        if not conn.execute("SELECT 1 FROM training_examples WHERE id=?", (example_id,)).fetchone():
            return None
        rows = conn.execute("""
            SELECT * FROM training_example_quality_reviews
            WHERE example_id=? ORDER BY reviewed_at,id
        """, (example_id,)).fetchall()
    return [dict(row) for row in rows]
