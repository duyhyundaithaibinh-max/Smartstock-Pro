"""Idempotently load the project's authored curriculum and create draft QA examples.

Run from backend/: python -m scripts.ingest_curriculum
All examples remain drafts until a human checks their answers and citations.
"""
from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path

from app import db, knowledge_base, training_room

ROOT = Path(__file__).resolve().parents[2]
CURRICULUM = ROOT / "training" / "curriculum"
SOURCE = "internal_curriculum_v1"
TOKEN = re.compile(r"[^\\W_]+", re.UNICODE)


def tokens(text: str) -> Counter[str]:
    return Counter(TOKEN.findall(text.casefold()))


def best_citation(document_id: int, question: str, answer: str) -> str:
    document = knowledge_base.get_document(document_id, include_chunks=True)
    if document is None or not document["chunks"]:
        raise RuntimeError(f"Curriculum document {document_id} has no indexed chunks.")
    wanted = tokens(question + " " + answer)
    ranked = []
    for chunk in document["chunks"]:
        overlap = sum((wanted & tokens(chunk["content"])).values())
        ranked.append((overlap, -chunk["chunk_index"], chunk["chunk_index"]))
    chunk_index = max(ranked)[2]
    if max(ranked)[0] == 0:
        raise RuntimeError(f"No source chunk matched the seeded example: {question}")
    return f"kb:{document_id}:{chunk_index}"


def main() -> None:
    db.init_db()
    document_ids: dict[str, int] = {}
    indexed = duplicates = 0
    for path in sorted(CURRICULUM.glob("*.md")):
        if path.name == "README.md":
            continue
        result = knowledge_base.ingest_document(
            path.name, path.read_bytes(), source=SOURCE, title=path.stem
        )
        document_ids[path.name] = int(result["id"])
        if result["status"] == "indexed":
            indexed += 1
        else:
            duplicates += 1

    seed_path = CURRICULUM / "examples.json"
    seeds = json.loads(seed_path.read_text(encoding="utf-8"))["examples"]
    existing = training_room.list_examples(limit=500)["items"]
    known_questions = {
        " ".join(item["question"].casefold().split()) for item in existing
    }
    created = skipped = 0
    for item in seeds:
        question_key = " ".join(item["question"].casefold().split())
        if question_key in known_questions:
            skipped += 1
            continue
        document_id = document_ids.get(item["document"])
        if document_id is None:
            raise RuntimeError(f"Missing curriculum document: {item['document']}")
        citation = best_citation(
            document_id, item["question"], item["expected_answer"]
        )
        training_room.create_example({
            "question": item["question"],
            "expected_answer": item["expected_answer"],
            "topic": item["topic"],
            "citation_ids": [citation],
        })
        known_questions.add(question_key)
        created += 1

    print(json.dumps({
        "source": SOURCE,
        "documents_indexed": indexed,
        "documents_already_present": duplicates,
        "draft_examples_created": created,
        "draft_examples_already_present": skipped,
        "note": "All seeded examples remain drafts and require human review.",
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
