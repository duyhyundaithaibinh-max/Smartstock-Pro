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
            VALUES(7,'Câu hỏi cũ','Câu trả lời cũ đủ dài để giữ nguyên','elliott','["kb:1:0"]',
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


    def test_patch_auth_is_route_specific_for_missing_legacy_and_owner(self):
        legacy = "legacy-training-review-token-" + "p" * 32
        with TestClient(app) as client:
            example = self._create(client)
            payload = {"expected_revision": 1, "topic": "new-topic"}
            self.assertEqual(client.patch(
                f"/api/v1/training/examples/{example['id']}", json=payload
            ).status_code, 401)
            with patch.dict(os.environ, {"SMARTSTOCK_API_TOKEN": legacy}):
                response = client.patch(
                    f"/api/v1/training/examples/{example['id']}", json=payload,
                    headers={"Authorization": f"Bearer {legacy}"},
                )
            self.assertEqual(response.status_code, 403)
            owner = client.patch(
                f"/api/v1/training/examples/{example['id']}", json=payload,
                headers=self.headers,
            )
            self.assertEqual(owner.status_code, 200, owner.text)
            self.assertEqual(owner.json()["revision"], 2)

    def test_approve_is_audited_and_repeat_approval_conflicts(self):
        with TestClient(app) as client:
            example = self._create(client)
            url = f"/api/v1/training/examples/{example['id']}/approve"
            approved = client.post(url, headers=self.headers)
            self.assertEqual(approved.status_code, 200, approved.text)
            self.assertEqual(client.post(url, headers=self.headers).status_code, 409)
            history = client.get(
                f"/api/v1/training/examples/{example['id']}/review-events",
                headers=self.headers,
            )
            self.assertEqual(history.status_code, 200)
            event = history.json()["items"][0]
            self.assertEqual(event["action"], "approved")
            self.assertEqual(event["reviewer_user_id"], 1)
            self.assertEqual(event["reviewer_label"], "Owner")
            self.assertEqual(event["revision_from"], 1)
            self.assertEqual(event["revision_to"], 1)

    def test_review_event_history_is_chronological_paginated_and_owner_only(self):
        with TestClient(app) as client:
            example = self._create(client)
            edit = client.patch(f"/api/v1/training/examples/{example['id']}", json={
                "expected_revision": 1, "topic": "updated-topic"
            }, headers=self.headers)
            self.assertEqual(edit.status_code, 200, edit.text)
            self.assertEqual(client.post(
                f"/api/v1/training/examples/{example['id']}/approve",
                headers=self.headers,
            ).status_code, 200)
            url = f"/api/v1/training/examples/{example['id']}/review-events"
            page1 = client.get(url + "?limit=1&offset=0", headers=self.headers)
            page2 = client.get(url + "?limit=1&offset=1", headers=self.headers)
            self.assertEqual(page1.status_code, 200)
            self.assertEqual(page2.status_code, 200)
            self.assertEqual(page1.json()["total"], 2)
            self.assertEqual(page1.json()["items"][0]["action"], "edited")
            self.assertEqual(page2.json()["items"][0]["action"], "approved")
            self.assertEqual(page1.json()["items"][0]["changed_fields"], ["topic"])
            self.assertNotIn("username", page1.text)
            self.assertNotIn("token", page1.text.lower())
            empty = self._create(client)
            empty_history = client.get(
                f"/api/v1/training/examples/{empty['id']}/review-events",
                headers=self.headers,
            )
            self.assertEqual(empty_history.status_code, 200)
            self.assertEqual(empty_history.json()["items"], [])
            self.assertEqual(empty_history.json()["total"], 0)
            self.assertEqual(client.get(url).status_code, 401)
            legacy = "legacy-training-review-token-" + "q" * 32
            with patch.dict(os.environ, {"SMARTSTOCK_API_TOKEN": legacy}):
                self.assertEqual(client.get(url, headers={
                    "Authorization": f"Bearer {legacy}"
                }).status_code, 403)
            self.assertEqual(client.get(
                "/api/v1/training/examples/999/review-events", headers=self.headers
            ).status_code, 404)
            for query in ("?limit=0", "?limit=101", "?offset=-1"):
                self.assertEqual(client.get(url + query, headers=self.headers).status_code, 422)

    def test_reject_edit_approve_audit_and_quality_rows_cascade_on_hard_delete(self):
        with TestClient(app) as client:
            approved = self._create(client)
            self.assertEqual(client.patch(
                f"/api/v1/training/examples/{approved['id']}",
                json={"expected_revision": 1, "topic": "changed"},
                headers=self.headers,
            ).status_code, 200)
            self.assertEqual(client.post(
                f"/api/v1/training/examples/{approved['id']}/approve",
                headers=self.headers,
            ).status_code, 200)
            rejected = self._create(client)
            self.assertEqual(client.post(
                f"/api/v1/training/examples/{rejected['id']}/reject",
                json={"reason": "Rejected for cascade test."},
                headers=self.headers,
            ).status_code, 200)
            for item in (approved, rejected):
                self.assertEqual(client.post(
                    f"/api/v1/training/examples/{item['id']}/quality-reviews",
                    json={"score": 100, "rubric_version": "qa-quality-v1",
                          "rationale": "Maximum score accepted for cascade test."},
                    headers=self.headers,
                ).status_code, 201)
            with db.connection() as conn:
                self.assertEqual(conn.execute(
                    "SELECT COUNT(*) FROM training_example_review_events"
                ).fetchone()[0], 3)
                self.assertEqual(conn.execute(
                    "SELECT COUNT(*) FROM training_example_quality_reviews"
                ).fetchone()[0], 2)
                with self.assertRaises(sqlite3.IntegrityError):
                    conn.execute("UPDATE training_example_review_events SET reason='tampered' WHERE id=1")
                with self.assertRaises(sqlite3.IntegrityError):
                    conn.execute("DELETE FROM training_example_review_events WHERE id=1")
                with self.assertRaises(sqlite3.IntegrityError):
                    conn.execute("UPDATE training_example_quality_reviews SET score=0 WHERE id=1")
                with self.assertRaises(sqlite3.IntegrityError):
                    conn.execute("DELETE FROM training_example_quality_reviews WHERE id=1")
            for item in (approved, rejected):
                self.assertEqual(client.delete(
                    f"/api/v1/training/examples/{item['id']}", headers=self.headers
                ).status_code, 200)
            with db.connection() as conn:
                self.assertEqual(conn.execute("SELECT COUNT(*) FROM training_examples").fetchone()[0], 0)
                self.assertEqual(conn.execute("SELECT COUNT(*) FROM training_example_review_events").fetchone()[0], 0)
                self.assertEqual(conn.execute("SELECT COUNT(*) FROM training_example_quality_reviews").fetchone()[0], 0)

    def test_approve_audit_failure_rolls_back_status(self):
        with TestClient(app) as client:
            example = self._create(client)
            with db.connection() as conn:
                conn.execute("""
                    CREATE TRIGGER fail_approve_event_insert
                    BEFORE INSERT ON training_example_review_events
                    WHEN NEW.action='approved'
                    BEGIN SELECT RAISE(ABORT, 'injected approval audit failure'); END
                """)
            with self.assertRaises(sqlite3.IntegrityError):
                training_room.approve_example(example["id"], 1)
            with db.connection() as conn:
                status = conn.execute(
                    "SELECT status FROM training_examples WHERE id=?", (example["id"],)
                ).fetchone()["status"]
                count = conn.execute("SELECT COUNT(*) FROM training_example_review_events").fetchone()[0]
            self.assertEqual(status, "draft")
            self.assertEqual(count, 0)

    def test_edit_audit_failure_rolls_back_content_and_revision(self):
        with TestClient(app) as client:
            example = self._create(client)
            with db.connection() as conn:
                conn.execute("""
                    CREATE TRIGGER fail_edit_event_insert
                    BEFORE INSERT ON training_example_review_events
                    WHEN NEW.action='edited'
                    BEGIN SELECT RAISE(ABORT, 'injected edit audit failure'); END
                """)
            with self.assertRaises(sqlite3.IntegrityError):
                training_room.edit_draft_example(
                    example["id"], {"expected_revision": 1, "topic": "must-rollback"}, 1
                )
            with db.connection() as conn:
                row = conn.execute(
                    "SELECT topic,revision FROM training_examples WHERE id=?", (example["id"],)
                ).fetchone()
                count = conn.execute("SELECT COUNT(*) FROM training_example_review_events").fetchone()[0]
            self.assertEqual(row["topic"], "elliott")
            self.assertEqual(row["revision"], 1)
            self.assertEqual(count, 0)

    def test_reject_and_approve_race_has_one_transition_and_one_event(self):
        with TestClient(app) as client:
            example = self._create(client)
            barrier = Barrier(2)

            def approve():
                barrier.wait()
                return training_room.approve_example(example["id"], 1)

            def reject():
                barrier.wait()
                return training_room.reject_example(example["id"], "Race rejection reason", 1)

            with ThreadPoolExecutor(max_workers=2) as pool:
                futures = [pool.submit(approve), pool.submit(reject)]
                outcomes = []
                for future in futures:
                    try:
                        outcomes.append(future.result(timeout=10))
                    except training_room.TrainingConflictError:
                        outcomes.append("conflict")
            self.assertEqual(sum(item != "conflict" for item in outcomes), 1)
            self.assertEqual(outcomes.count("conflict"), 1)
            with db.connection() as conn:
                row = conn.execute(
                    "SELECT status FROM training_examples WHERE id=?", (example["id"],)
                ).fetchone()
                events = conn.execute(
                    "SELECT action FROM training_example_review_events WHERE example_id=?",
                    (example["id"],),
                ).fetchall()
            self.assertIn(row["status"], ("approved", "rejected"))
            self.assertEqual(len(events), 1)
            self.assertEqual(events[0]["action"], row["status"])

    def test_quality_review_accepts_all_existing_statuses_and_does_not_change_evaluator(self):
        with TestClient(app) as client:
            draft = self._create(client)
            approved = self._create(client)
            rejected = self._create(client)
            self.assertEqual(client.post(
                f"/api/v1/training/examples/{approved['id']}/approve",
                headers=self.headers,
            ).status_code, 200)
            self.assertEqual(client.post(
                f"/api/v1/training/examples/{rejected['id']}/reject",
                json={"reason": "Rejected but still quality-reviewable."},
                headers=self.headers,
            ).status_code, 200)
            for item, score in ((draft, 0), (approved, 100), (rejected, 50)):
                response = client.post(
                    f"/api/v1/training/examples/{item['id']}/quality-reviews",
                    json={"score": score, "rubric_version": "qa-quality-v1",
                          "rationale": "Manual review allowed on every current status."},
                    headers=self.headers,
                )
                self.assertEqual(response.status_code, 201, response.text)
                self.assertEqual(response.json()["score"], score)
            before = client.get("/api/v1/training/evaluation", headers=self.headers).json()
            predictions = {"predictions": [{
                "example_id": approved["id"],
                "answer": approved["expected_answer"],
                "citation_ids": [self.citation],
            }]}
            evaluator_before = client.post(
                "/api/v1/training/evaluation/predictions", json=predictions, headers=self.headers
            ).json()
            self.assertEqual(client.post(
                f"/api/v1/training/examples/{draft['id']}/quality-reviews",
                json={"score": 100, "rubric_version": "qa-quality-v1",
                      "rationale": "Second append-only review for draft."},
                headers=self.headers,
            ).status_code, 201)
            after = client.get("/api/v1/training/evaluation", headers=self.headers).json()
            evaluator_after = client.post(
                "/api/v1/training/evaluation/predictions", json=predictions, headers=self.headers
            ).json()
            self.assertEqual(before, after)
            self.assertEqual(evaluator_before, evaluator_after)

    def test_legacy_migration_preserves_all_fields_is_idempotent_and_rolls_back_on_failure(self):
        path = Path(self.temp_dir.name) / "legacy-full.db"

        def build_legacy():
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
                VALUES(41,'Unicode câu hỏi','Unicode câu trả lời','chu kỳ','["kb:3:4"]',
                       'draft','2026-01-01T00:00:00','2026-01-02T00:00:00')
            """)
            conn.execute("""
                INSERT INTO training_examples
                    (id,question,expected_answer,topic,citation_ids,status,created_at,updated_at)
                VALUES(42,'Approved question','Approved answer','elliott','["kb:4:2"]',
                       'approved','2026-02-01T00:00:00','2026-02-02T00:00:00')
            """)
            conn.commit()
            return conn

        conn = build_legacy()

        def authorizer(action, arg1, arg2, database, trigger):
            if action == sqlite3.SQLITE_CREATE_INDEX and arg1 == "idx_training_examples_status_created":
                return sqlite3.SQLITE_DENY
            return sqlite3.SQLITE_OK

        conn.set_authorizer(authorizer)
        with self.assertRaises(sqlite3.DatabaseError):
            db._migrate_training_review(conn)
        conn.set_authorizer(None)
        conn.rollback()
        old_sql = conn.execute(
            "SELECT sql FROM sqlite_master WHERE type='table' AND name='training_examples'"
        ).fetchone()["sql"]
        self.assertNotIn("'rejected'", old_sql)
        self.assertNotIn("revision", [x["name"] for x in conn.execute("PRAGMA table_info(training_examples)")])
        self.assertEqual(conn.execute("SELECT COUNT(*) FROM training_examples").fetchone()[0], 2)

        db._migrate_training_review(conn)
        conn.commit()
        rows = conn.execute("SELECT * FROM training_examples ORDER BY id").fetchall()
        self.assertEqual([row["id"] for row in rows], [41, 42])
        self.assertEqual(rows[0]["question"], "Unicode câu hỏi")
        self.assertEqual(rows[0]["expected_answer"], "Unicode câu trả lời")
        self.assertEqual(rows[0]["topic"], "chu kỳ")
        self.assertEqual(rows[0]["citation_ids"], '["kb:3:4"]')
        self.assertEqual(rows[0]["status"], "draft")
        self.assertEqual(rows[0]["created_at"], "2026-01-01T00:00:00")
        self.assertEqual(rows[0]["updated_at"], "2026-01-02T00:00:00")
        self.assertEqual([row["revision"] for row in rows], [1, 1])
        self.assertEqual(rows[1]["question"], "Approved question")
        self.assertEqual(rows[1]["expected_answer"], "Approved answer")
        self.assertEqual(rows[1]["topic"], "elliott")
        self.assertEqual(rows[1]["citation_ids"], '["kb:4:2"]')
        self.assertEqual(rows[1]["status"], "approved")
        self.assertEqual(rows[1]["created_at"], "2026-02-01T00:00:00")
        self.assertEqual(rows[1]["updated_at"], "2026-02-02T00:00:00")
        self.assertEqual(conn.execute("PRAGMA foreign_key_check").fetchall(), [])
        index_names = {row["name"] for row in conn.execute("PRAGMA index_list(training_examples)")}
        self.assertIn("idx_training_examples_status_created", index_names)
        event_indexes = {row["name"] for row in conn.execute("PRAGMA index_list(training_example_review_events)")}
        self.assertIn("idx_training_review_events_example", event_indexes)
        quality_indexes = {row["name"] for row in conn.execute("PRAGMA index_list(training_example_quality_reviews)")}
        self.assertIn("idx_training_quality_reviews_example", quality_indexes)
        trigger_names = {row["name"] for row in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='trigger'"
        )}
        self.assertTrue({
            "trg_training_review_events_no_update", "trg_training_review_events_no_delete",
            "trg_training_quality_reviews_no_update", "trg_training_quality_reviews_no_delete",
        }.issubset(trigger_names))
        snapshot = [tuple(row) for row in rows]
        db._migrate_training_review(conn)
        conn.commit()
        self.assertEqual(snapshot, [tuple(row) for row in conn.execute(
            "SELECT * FROM training_examples ORDER BY id"
        )])
        self.assertEqual(conn.execute("PRAGMA foreign_key_check").fetchall(), [])
        conn.close()
        with patch("app.db.DB_PATH", str(path)):
            db.init_db()
            db.init_db()
        check = sqlite3.connect(path)
        self.assertEqual(check.execute("SELECT COUNT(*) FROM training_examples").fetchone()[0], 2)
        check.close()


    def test_pr25_event_schema_migration_preserves_existing_events_without_backfill(self):
        path = Path(self.temp_dir.name) / "pr25-review.db"
        conn = sqlite3.connect(path)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys=ON")
        conn.execute("CREATE TABLE auth_users(id INTEGER PRIMARY KEY)")
        conn.execute("INSERT INTO auth_users(id) VALUES(1)")
        conn.execute("""
            CREATE TABLE training_examples (
                id INTEGER PRIMARY KEY,
                question TEXT NOT NULL,
                expected_answer TEXT NOT NULL,
                topic TEXT NOT NULL,
                citation_ids TEXT NOT NULL,
                status TEXT NOT NULL CHECK(status IN ('draft','approved','rejected')),
                revision INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
        """)
        conn.execute("""
            INSERT INTO training_examples VALUES
                (51,'Approved legacy example','Answer body','topic','["kb:1:0"]',
                 'approved',1,'2026-03-01','2026-03-02')
        """)
        conn.execute("""
            CREATE TABLE training_example_review_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                example_id INTEGER NOT NULL,
                action TEXT NOT NULL CHECK(action IN ('rejected','edited')),
                reason TEXT,
                revision_from INTEGER NOT NULL,
                revision_to INTEGER NOT NULL,
                changed_fields TEXT NOT NULL DEFAULT '[]',
                reviewer_user_id INTEGER NOT NULL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY(example_id) REFERENCES training_examples(id) ON DELETE CASCADE,
                FOREIGN KEY(reviewer_user_id) REFERENCES auth_users(id) ON DELETE RESTRICT
            )
        """)
        conn.execute("""
            INSERT INTO training_example_review_events
                (id,example_id,action,reason,revision_from,revision_to,changed_fields,
                 reviewer_user_id,created_at)
            VALUES(71,51,'edited',NULL,1,2,'["topic"]',1,'2026-03-03')
        """)
        conn.commit()
        db._migrate_training_review(conn)
        conn.commit()
        event = conn.execute(
            "SELECT * FROM training_example_review_events WHERE id=71"
        ).fetchone()
        self.assertEqual(event["action"], "edited")
        self.assertEqual(event["changed_fields"], '["topic"]')
        self.assertEqual(event["created_at"], "2026-03-03")
        self.assertEqual(conn.execute(
            "SELECT COUNT(*) FROM training_example_review_events WHERE action='approved'"
        ).fetchone()[0], 0, "migration must not fabricate historical approval events")
        conn.execute("""
            INSERT INTO training_example_review_events
                (example_id,action,reason,revision_from,revision_to,changed_fields,reviewer_user_id)
            VALUES(51,'approved',NULL,1,1,'[]',1)
        """)
        self.assertEqual(conn.execute(
            "SELECT COUNT(*) FROM training_example_review_events"
        ).fetchone()[0], 2)
        conn.commit()
        self.assertEqual(conn.execute("PRAGMA foreign_key_check").fetchall(), [])
        conn.close()


if __name__ == "__main__":
    unittest.main()
