import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi import HTTPException

from app import db, knowledge_base, training_room
from app.routers import market


class TrainingRoomTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.temp_dir.name) / "training-room.db"
        self.patch_db = patch("app.db.DB_PATH", str(self.db_path))
        self.patch_db.start()
        db.init_db()
        self.document = knowledge_base.ingest_document(
            "elliott.md",
            ("Elliott Wave impulse requires Wave 3 not to be the shortest. "
             "Wave 2 must not retrace beyond the start of Wave 1. " * 8).encode(),
            source="reviewed_research",
            title="Elliott Wave rules",
        )
        self.citation = "kb:1:0"

    def tearDown(self):
        self.patch_db.stop()
        self.temp_dir.cleanup()

    def _payload(self, question="Điều kiện nào xác nhận sóng Elliott số 3?",
                 answer="Sóng 3 không được là sóng ngắn nhất trong cấu trúc đẩy."):
        return {
            "question": question,
            "expected_answer": answer,
            "topic": "elliott",
            "citation_ids": [self.citation],
        }

    def test_create_example_starts_as_draft_and_is_source_grounded(self):
        item = market.create_training_example(self._payload())
        self.assertEqual(item["status"], "draft")
        self.assertEqual(item["citation_ids"], [self.citation])
        self.assertEqual(item["topic"], "elliott")

    def test_create_validates_citations_within_insert_transaction(self):
        with patch.object(training_room, "connection", wraps=training_room.connection) as connection_spy:
            item = training_room.create_example(self._payload())

        self.assertEqual(item["status"], "draft")
        self.assertEqual(connection_spy.call_count, 1)

    def test_rejects_nonexistent_source_citation(self):
        payload = self._payload()
        payload["citation_ids"] = ["kb:999:0"]
        with self.assertRaises(HTTPException) as error:
            market.create_training_example(payload)
        self.assertEqual(error.exception.status_code, 422)

    def test_approval_and_export_include_only_reviewed_examples(self):
        draft = market.create_training_example(self._payload())
        self.assertEqual(market.export_training_dataset()["count"], 0)

        approved = market.approve_training_example(draft["id"])
        exported = market.export_training_dataset()

        self.assertEqual(approved["status"], "approved")
        self.assertEqual(exported["count"], 1)
        row = json.loads(exported["content"])
        self.assertEqual(row["messages"][0]["role"], "user")
        self.assertEqual(row["messages"][1]["content"], draft["expected_answer"])
        self.assertEqual(row["metadata"]["citation_ids"], [self.citation])

    def test_deleted_source_prevents_later_approval(self):
        draft = market.create_training_example(self._payload())
        knowledge_base.delete_document(self.document["id"])
        with self.assertRaises(HTTPException) as error:
            market.approve_training_example(draft["id"])
        self.assertEqual(error.exception.status_code, 422)

    def test_export_excludes_approved_examples_after_source_deletion(self):
        draft = market.create_training_example(self._payload())
        market.approve_training_example(draft["id"])
        knowledge_base.delete_document(self.document["id"])

        exported = market.export_training_dataset()
        report = market.evaluate_training_dataset()

        self.assertEqual(exported["count"], 0)
        self.assertEqual(report["approved_examples"], 1)
        self.assertEqual(report["valid_approved_examples"], 0)
        self.assertEqual(report["approved_examples_with_missing_sources"], 1)

    def test_evaluation_reports_duplicates_and_review_counts(self):
        market.create_training_example(self._payload())
        market.create_training_example(self._payload(
            question="  ĐIỀU KIỆN NÀO XÁC NHẬN SÓNG ELLIOTT SỐ 3? "
        ))

        report = market.evaluate_training_dataset()

        self.assertEqual(report["total_examples"], 2)
        self.assertEqual(report["draft_examples"], 2)
        self.assertEqual(report["approved_examples"], 0)
        self.assertEqual(report["duplicate_question_groups"], 1)
        self.assertEqual(report["readiness"], "collect_and_review_more_examples")

    def test_api_listing_filters_status(self):
        market.create_training_example(self._payload())
        result = market.list_training_examples(limit=20, offset=0, status="draft")
        self.assertEqual(result["total"], 1)
        self.assertEqual(result["items"][0]["status"], "draft")


if __name__ == "__main__":
    unittest.main()
