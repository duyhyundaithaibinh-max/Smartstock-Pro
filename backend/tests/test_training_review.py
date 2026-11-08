import os
import sqlite3
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient

from app import auth, db, training_room
from app.main import app


class TrainingReviewApiTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.temp_dir.name) / "review.db"
        self.db_patch = patch("app.db.DB_PATH", str(self.db_path))
        self.db_patch.start()
        self.env_patch = patch.dict(os.environ, {"SMARTSTOCK_API_TOKEN": ""})
        self.env_patch.start()
        db.init_db()
        auth.ensure_bootstrap_secret()
        secret = auth.read_bootstrap_secret()
        with TestClient(app) as client:
            setup = client.post("/api/v1/auth/register-first-owner", json={
                "username": "owner", "password": "a-long-test-password",
                "bootstrap_secret": secret,
            })
            self.assertEqual(setup.status_code, 201, setup.text)
            login = client.post("/api/v1/auth/login", json={
                "username": "owner", "password": "a-long-test-password",
            })
            self.headers = {"Authorization": f"Bearer {login.json()['access_token']}"}
            source = client.post("/api/v1/knowledge/documents", files={
                "file": ("source.md", b"# Source\nWave 3 is not the shortest impulse wave.", "text/markdown")
            }, headers=self.headers)
            self.assertEqual(source.status_code, 201, source.text)
            self.citation = f"kb:{source.json()['id']}:0"

    def tearDown(self):
        self.env_patch.stop()
        self.db_patch.stop()
        self.temp_dir.cleanup()

    def _create(self, client):
        response = client.post("/api/v1/training/examples", json={
            "question": "What is the Elliott Wave rule for wave three?",
            "expected_answer": "Wave three must not be the shortest impulse wave.",
            "topic": "elliott", "citation_ids": [self.citation],
        }, headers=self.headers)
        self.assertEqual(response.status_code, 201, response.text)
        return response.json()

    def test_reject_draft_writes_reason_actor_and_timestamp(self):
        with TestClient(app) as client:
            example = self._create(client)
            response = client.post(f"/api/v1/training/examples/{example['id']}/reject",
                json={"reason": "  Citation needs a better source.  "}, headers=self.headers)
            self.assertEqual(response.status_code, 200, response.text)
            self.assertEqual(response.json()["status"], "rejected")
            with db.connection() as conn:
                event = conn.execute("SELECT * FROM training_example_review_events").fetchone()
            self.assertEqual(event["action"], "rejected")
            self.assertEqual(event["reason"], "Citation needs a better source.")
            self.assertEqual(event["reviewer_user_id"], 1)
            self.assertTrue(event["created_at"])

    def test_reject_missing_invalid_repeat_and_approved_conflict(self):
        with TestClient(app) as client:
            self.assertEqual(client.post("/api/v1/training/examples/999/reject",
                json={"reason": "Not suitable for training"}, headers=self.headers).status_code, 404)
            example = self._create(client)
            for reason in ("", "   ", "x" * 1001):
                response = client.post(f"/api/v1/training/examples/{example['id']}/reject",
                    json={"reason": reason}, headers=self.headers)
                self.assertEqual(response.status_code, 422)
            approved = client.post(f"/api/v1/training/examples/{example['id']}/approve",
                headers=self.headers)
            self.assertEqual(approved.status_code, 200)
            conflict = client.post(f"/api/v1/training/examples/{example['id']}/reject",
                json={"reason": "Too late"}, headers=self.headers)
            self.assertEqual(conflict.status_code, 409)

    def test_reject_requires_owner_and_legacy_token_is_forbidden(self):
        legacy = "legacy-training-review-token-" + "z" * 32
        with TestClient(app) as client:
            example = self._create(client)
            self.assertEqual(client.post(f"/api/v1/training/examples/{example['id']}/reject",
                json={"reason": "Needs review"}).status_code, 401)
            with patch.dict(os.environ, {"SMARTSTOCK_API_TOKEN": legacy}):
                response = client.post(f"/api/v1/training/examples/{example['id']}/reject",
                    json={"reason": "Needs review"},
                    headers={"Authorization": f"Bearer {legacy}"})
            self.assertEqual(response.status_code, 403)

    def test_edit_draft_uses_revision_guard_and_audit(self):
        with TestClient(app) as client:
            example = self._create(client)
            edited = client.patch(f"/api/v1/training/examples/{example['id']}", json={
                "expected_revision": 1,
                "question": "What is the strict Elliott Wave rule for wave three?"
            }, headers=self.headers)
            self.assertEqual(edited.status_code, 200, edited.text)
            self.assertEqual(edited.json()["revision"], 2)
            self.assertEqual(edited.json()["status"], "draft")
            stale = client.patch(f"/api/v1/training/examples/{example['id']}", json={
                "expected_revision": 1, "topic": "new-topic"
            }, headers=self.headers)
            self.assertEqual(stale.status_code, 409)
            with db.connection() as conn:
                event = conn.execute("SELECT * FROM training_example_review_events WHERE action='edited'").fetchone()
            self.assertEqual(event["revision_from"], 1)
            self.assertEqual(event["revision_to"], 2)
            self.assertEqual(event["reviewer_user_id"], 1)

    def test_edit_rejects_invalid_fields_citations_and_non_draft(self):
        with TestClient(app) as client:
            example = self._create(client)
            self.assertEqual(client.patch(f"/api/v1/training/examples/{example['id']}", json={
                "expected_revision": 1, "citation_ids": ["kb:999:0"]
            }, headers=self.headers).status_code, 422)
            self.assertEqual(client.patch(f"/api/v1/training/examples/{example['id']}", json={
                "expected_revision": 1, "reviewer_user_id": 99
            }, headers=self.headers).status_code, 422)
            self.assertEqual(client.post(f"/api/v1/training/examples/{example['id']}/approve",
                headers=self.headers).status_code, 200)
            self.assertEqual(client.patch(f"/api/v1/training/examples/{example['id']}", json={
                "expected_revision": 1, "topic": "edited"
            }, headers=self.headers).status_code, 409)

    def test_quality_review_history_is_append_only_and_revision_scoped(self):
        with TestClient(app) as client:
            example = self._create(client)
            url = f"/api/v1/training/examples/{example['id']}/quality-reviews"
            first = client.post(url, json={"score": 86, "rubric_version": "qa-quality-v1",
                "rationale": "Correct and source-grounded answer."}, headers=self.headers)
            self.assertEqual(first.status_code, 201, first.text)
            self.assertEqual(first.json()["example_revision"], 1)
            client.patch(f"/api/v1/training/examples/{example['id']}", json={
                "expected_revision": 1, "topic": "elliott-updated"
            }, headers=self.headers)
            second = client.post(url, json={"score": 92, "rubric_version": "qa-quality-v1",
                "rationale": "Improved topic precision and source mapping."}, headers=self.headers)
            self.assertEqual(second.status_code, 201, second.text)
            self.assertEqual(second.json()["example_revision"], 2)
            history = client.get(url, headers=self.headers)
            self.assertEqual(history.status_code, 200)
            self.assertEqual(history.json()["count"], 2)
            self.assertEqual([x["example_revision"] for x in history.json()["items"]], [1, 2])
            with db.connection() as conn:
                with self.assertRaises(Exception):
                    conn.execute("UPDATE training_example_quality_reviews SET score=0 WHERE id=1")

    def test_quality_review_validation_and_owner_only_auth(self):
        with TestClient(app) as client:
            example = self._create(client)
            url = f"/api/v1/training/examples/{example['id']}/quality-reviews"
            valid = {"score": 80, "rubric_version": "qa-quality-v1",
                     "rationale": "This example is accurate and well cited."}
            for score in (-1, 101, 80.5, True, None):
                self.assertEqual(client.post(url, json=dict(valid, score=score),
                    headers=self.headers).status_code, 422)
            for rubric in ("unknown-v9", ""):
                self.assertEqual(client.post(url, json=dict(valid, rubric_version=rubric),
                    headers=self.headers).status_code, 422)
            self.assertEqual(client.post(url, json=dict(valid, reviewer_user_id=9),
                headers=self.headers).status_code, 422)
            self.assertEqual(client.post(url, json=valid).status_code, 401)

    def test_rejected_examples_are_not_readiness_drafts_or_exported(self):
        with TestClient(app) as client:
            example = self._create(client)
            client.post(f"/api/v1/training/examples/{example['id']}/reject",
                json={"reason": "Not sufficiently supported."}, headers=self.headers)
            listing = client.get("/api/v1/training/examples?status=rejected", headers=self.headers)
            self.assertEqual(listing.status_code, 200)
            self.assertEqual(listing.json()["items"][0]["status"], "rejected")
            readiness = client.get("/api/v1/training/evaluation", headers=self.headers).json()
            self.assertEqual(readiness["rejected_examples"], 1)
            self.assertEqual(readiness["draft_examples"], 0)
            self.assertEqual(client.get("/api/v1/training/export", headers=self.headers).json()["count"], 0)

    def test_delete_remains_hard_delete_and_cascades_review_history(self):
        with TestClient(app) as client:
            example = self._create(client)
            url = f"/api/v1/training/examples/{example['id']}/quality-reviews"
            client.post(url, json={"score": 70, "rubric_version": "qa-quality-v1",
                "rationale": "Adequate answer but source is narrow."}, headers=self.headers)
            self.assertEqual(client.delete(f"/api/v1/training/examples/{example['id']}",
                headers=self.headers).status_code, 200)
            with db.connection() as conn:
                self.assertEqual(conn.execute("SELECT COUNT(*) FROM training_examples").fetchone()[0], 0)
                self.assertEqual(conn.execute("SELECT COUNT(*) FROM training_example_quality_reviews").fetchone()[0], 0)

    def test_review_endpoints_reject_legacy_token_for_read_and_write(self):
        legacy = "legacy-training-review-token-" + "x" * 32
        with TestClient(app) as client:
            example = self._create(client)
            url = f"/api/v1/training/examples/{example['id']}/quality-reviews"
            with patch.dict(os.environ, {"SMARTSTOCK_API_TOKEN": legacy}):
                headers = {"Authorization": f"Bearer {legacy}"}
                self.assertEqual(client.get(url, headers=headers).status_code, 403)
                self.assertEqual(client.post(url, json={"score": 50, "rubric_version": "qa-quality-v1",
                    "rationale": "Review from legacy token must fail."}, headers=headers).status_code, 403)


    def test_reject_update_and_audit_insert_roll_back_together(self):
        with TestClient(app) as client:
            example = self._create(client)
            with db.connection() as conn:
                conn.execute("""
                    CREATE TRIGGER fail_review_event_insert
                    BEFORE INSERT ON training_example_review_events
                    BEGIN SELECT RAISE(ABORT, 'injected audit failure'); END
                """)
            with self.assertRaises(sqlite3.IntegrityError):
                training_room.reject_example(example["id"], "A valid rejection reason", 1)
            with db.connection() as conn:
                row = conn.execute("SELECT status FROM training_examples WHERE id=?",
                                   (example["id"],)).fetchone()
                count = conn.execute("SELECT COUNT(*) FROM training_example_review_events").fetchone()[0]
            self.assertEqual(row["status"], "draft")
            self.assertEqual(count, 0)

    def test_concurrent_edits_with_same_revision_allow_exactly_one_writer(self):
        with TestClient(app) as client:
            example = self._create(client)
            barrier = Barrier(2)

            def edit(topic):
                barrier.wait()
                return training_room.edit_draft_example(
                    example["id"], {"expected_revision": 1, "topic": topic}, 1
                )

            with ThreadPoolExecutor(max_workers=2) as pool:
                futures = [pool.submit(edit, "topic-a"), pool.submit(edit, "topic-b")]
                outcomes = []
                for future in futures:
                    try:
                        outcomes.append(future.result(timeout=10))
                    except training_room.TrainingConflictError:
                        outcomes.append("conflict")
            self.assertEqual(sum(item != "conflict" for item in outcomes), 1)
            self.assertEqual(outcomes.count("conflict"), 1)
            with db.connection() as conn:
                row = conn.execute("SELECT revision FROM training_examples WHERE id=?",
                                   (example["id"],)).fetchone()
            self.assertEqual(row["revision"], 2)

    def test_legacy_schema_migration_preserves_ids_content_and_foreign_keys(self):
        path = Path(self.temp_dir.name) / "legacy.db"
        conn = sqlite3.connect(path)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys=ON")
        conn.execute("CREATE TABLE auth_users(id INTEGER PRIMARY KEY)")
        conn.execute("""
            CREATE TABLE training_examples (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                question TEXT NOT NULL,
                expected_answer TEXT NOT NULL,
                topic TEXT NOT NULL DEFAULT 'general',
                citation_ids TEXT NOT NULL,
                status TEXT NOT NULL CHECK(status IN ('draft','approved')) DEFAULT 'draft',
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        """)
        conn.execute("CREATE INDEX idx_training_examples_status_created ON training_examples(status, created_at)")
        conn.execute("""
            INSERT INTO training_examples
                (id,question,expected_answer,topic,citation_ids,status,created_at,updated_at)
            VALUES(7,'Câu hỏi cũ','Câu trả lời cũ đủ dài để giữ nguyên','elliott','[""kb:1:0""]',
                   'approved','2026-01-01T00:00:00','2026-01-02T00:00:00')
        """)
        conn.commit()
        db._migrate_training_review(conn)
        row = conn.execute("SELECT * FROM training_examples WHERE id=7").fetchone()
        self.assertEqual(row["question"], "Câu hỏi cũ")
        self.assertEqual(row["expected_answer"], "Câu trả lời cũ đủ dài để giữ nguyên")
        self.assertEqual(row["status"], "approved")
        self.assertEqual(row["revision"], 1)
        self.assertEqual(row["created_at"], "2026-01-01T00:00:00")
        conn.execute("UPDATE training_examples SET status='rejected' WHERE id=7")
        self.assertEqual(conn.execute("PRAGMA foreign_key_check").fetchall(), [])
        conn.close()


if __name__ == "__main__":
    unittest.main()
