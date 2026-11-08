import hashlib
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient

from app import auth, db
from app.main import app


class EndpointAuthRegressionTests(unittest.TestCase):
    """HTTP-level auth regression tests for routes protected by the app middleware."""

    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.temp_dir.name) / "endpoint-auth.db"
        self.patch_db = patch("app.db.DB_PATH", str(self.db_path))
        self.patch_db.start()
        self.patch_env = patch.dict(os.environ, {"SMARTSTOCK_API_TOKEN": ""})
        self.patch_env.start()
        db.init_db()
        auth.ensure_bootstrap_secret()
        self.bootstrap_secret = auth.read_bootstrap_secret()

    def tearDown(self):
        self.patch_env.stop()
        self.patch_db.stop()
        self.temp_dir.cleanup()

    def _owner_headers(self, client):
        setup = client.post("/api/v1/auth/register-first-owner", json={
            "username": "owner",
            "password": "a-long-test-password",
            "bootstrap_secret": self.bootstrap_secret,
        })
        self.assertEqual(setup.status_code, 201, setup.text)
        login = client.post("/api/v1/auth/login", json={
            "username": "owner",
            "password": "a-long-test-password",
        })
        self.assertEqual(login.status_code, 200, login.text)
        return {"Authorization": f"Bearer {login.json()['access_token']}"}

    @staticmethod
    def _invalid_headers():
        return {"Authorization": "Bearer " + "x" * 48}

    def _upload_source(self, client, headers):
        response = client.post(
            "/api/v1/knowledge/documents",
            files={"file": (
                "endpoint-auth-source.md",
                b"# Elliott Wave\nWave 3 is not the shortest wave in an impulse structure.",
                "text/markdown",
            )},
            headers=headers,
        )
        self.assertEqual(response.status_code, 201, response.text)
        return response.json()["id"]

    def _create_example(self, client, headers, document_id):
        response = client.post("/api/v1/training/examples", json={
            "question": "What is the Elliott Wave rule for wave three?",
            "expected_answer": "Wave three must not be the shortest impulse wave.",
            "topic": "elliott",
            "citation_ids": [f"kb:{document_id}:0"],
        }, headers=headers)
        self.assertEqual(response.status_code, 201, response.text)
        return response.json()["id"]

    def test_auth_status_payload_and_me_valid_missing_invalid_expired_revoked(self):
        with TestClient(app) as client:
            status = client.get("/api/v1/auth/status")
            self.assertEqual(status.status_code, 200)
            self.assertEqual(status.json(), {
                "owner_initialized": False,
                "registration": "first_owner_only",
            })
            self.assertEqual(client.get("/api/v1/auth/me").status_code, 401)
            self.assertEqual(
                client.get("/api/v1/auth/me", headers=self._invalid_headers()).status_code,
                401,
            )

            owner_headers = self._owner_headers(client)
            me = client.get("/api/v1/auth/me", headers=owner_headers)
            self.assertEqual(me.status_code, 200)
            self.assertEqual(me.json(), {"id": 1, "username": "owner", "role": "owner"})
            self.assertEqual(client.get("/api/v1/auth/status").json(), {
                "owner_initialized": True,
                "registration": "first_owner_only",
            })

            expired = client.post("/api/v1/auth/login", json={
                "username": "owner", "password": "a-long-test-password"
            }).json()["access_token"]
            with db.connection() as conn:
                conn.execute(
                    "UPDATE auth_sessions SET expires_at='2000-01-01T00:00:00+00:00' "
                    "WHERE token_sha256=?",
                    (hashlib.sha256(expired.encode()).hexdigest(),),
                )
            self.assertEqual(
                client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {expired}"}).status_code,
                401,
            )

            revoked = client.post("/api/v1/auth/login", json={
                "username": "owner", "password": "a-long-test-password"
            }).json()["access_token"]
            logout = client.post(
                "/api/v1/auth/logout", headers={"Authorization": f"Bearer {revoked}"}
            )
            self.assertEqual(logout.status_code, 200)
            self.assertEqual(
                client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {revoked}"}).status_code,
                401,
            )

    def test_logout_rejects_missing_invalid_and_replayed_sessions(self):
        with TestClient(app) as client:
            self.assertEqual(client.post("/api/v1/auth/logout").status_code, 401)
            self.assertEqual(
                client.post("/api/v1/auth/logout", headers=self._invalid_headers()).status_code,
                401,
            )
            owner_headers = self._owner_headers(client)
            self.assertEqual(client.post("/api/v1/auth/logout", headers=owner_headers).status_code, 200)
            self.assertEqual(client.post("/api/v1/auth/logout", headers=owner_headers).status_code, 401)

    def test_chart_and_analysis_get_allowlist_is_method_specific(self):
        public_gets = (
            "/api/v1/candles/chart?symbol=FPT",
            "/api/v1/analysis/price-action?symbol=FPT",
            "/api/v1/analysis/fibonacci?symbol=FPT",
            "/api/v1/analysis/elliott?symbol=FPT",
            "/api/v1/analysis/volume-flow?symbol=FPT",
            "/api/v1/analysis/report?symbol=FPT",
        )
        with TestClient(app) as client:
            for path in public_gets:
                response = client.get(path)
                self.assertNotEqual(response.status_code, 401, path)

            # The same path does not become public for non-GET methods.
            protected_writes = (
                ("POST", "/api/v1/candles/chart"),
                ("PUT", "/api/v1/analysis/price-action"),
                ("DELETE", "/api/v1/analysis/fibonacci"),
                ("POST", "/api/v1/analysis/report"),
            )
            for method, path in protected_writes:
                response = client.request(method, path)
                self.assertEqual(response.status_code, 401, f"{method} {path}")

    def test_watchlist_get_requires_owner_or_configured_legacy_token(self):
        with TestClient(app) as client:
            owner_headers = self._owner_headers(client)
            created = client.post("/api/v1/symbols", json={
                "symbol": "FPT", "name": "FPT Corporation", "exchange": "HOSE"
            }, headers=owner_headers)
            self.assertEqual(created.status_code, 201, created.text)

            self.assertEqual(client.get("/api/v1/watchlist").status_code, 401)
            self.assertEqual(
                client.get("/api/v1/watchlist", headers=self._invalid_headers()).status_code,
                401,
            )
            owner_read = client.get("/api/v1/watchlist", headers=owner_headers)
            self.assertEqual(owner_read.status_code, 200)
            self.assertEqual([item["symbol"] for item in owner_read.json()["items"]], ["FPT"])

            legacy = "legacy-endpoint-regression-token-" + "z" * 32
            with patch.dict(os.environ, {"SMARTSTOCK_API_TOKEN": legacy}):
                legacy_read = client.get(
                    "/api/v1/watchlist", headers={"Authorization": f"Bearer {legacy}"}
                )
                missing_read = client.get("/api/v1/watchlist")
            self.assertEqual(legacy_read.status_code, 200)
            self.assertEqual(missing_read.status_code, 401)

    def test_knowledge_get_routes_and_write_routes_enforce_owner_auth(self):
        with TestClient(app) as client:
            owner_headers = self._owner_headers(client)
            document_id = self._upload_source(client, owner_headers)
            get_routes = (
                "/api/v1/knowledge/documents",
                "/api/v1/knowledge/search?q=Elliott",
                f"/api/v1/knowledge/documents/{document_id}",
                f"/api/v1/knowledge/citations/{document_id}/0",
            )
            for path in get_routes:
                self.assertEqual(client.get(path).status_code, 401, path)
                self.assertEqual(
                    client.get(path, headers=self._invalid_headers()).status_code,
                    401,
                    path,
                )
                response = client.get(path, headers=owner_headers)
                self.assertEqual(response.status_code, 200, f"{path}: {response.text}")

            legacy = "legacy-knowledge-regression-token-" + "y" * 32
            with patch.dict(os.environ, {"SMARTSTOCK_API_TOKEN": legacy}):
                legacy_list = client.get(
                    "/api/v1/knowledge/documents",
                    headers={"Authorization": f"Bearer {legacy}"},
                )
            self.assertEqual(legacy_list.status_code, 200)

            upload = {
                "file": ("second-source.txt", b"Second knowledge source for delete auth.", "text/plain")
            }
            self.assertEqual(
                client.post("/api/v1/knowledge/documents", files=upload).status_code,
                401,
            )
            created = client.post(
                "/api/v1/knowledge/documents",
                files=upload,
                headers=owner_headers,
            )
            self.assertEqual(created.status_code, 201, created.text)
            second_id = created.json()["id"]
            self.assertEqual(
                client.delete(f"/api/v1/knowledge/documents/{second_id}").status_code,
                401,
            )
            self.assertEqual(
                client.delete(
                    f"/api/v1/knowledge/documents/{second_id}", headers=owner_headers
                ).status_code,
                200,
            )

    def test_training_create_delete_readiness_and_predictions_require_owner(self):
        with TestClient(app) as client:
            owner_headers = self._owner_headers(client)
            document_id = self._upload_source(client, owner_headers)
            payload = {
                "question": "What is the Elliott Wave rule for wave three?",
                "expected_answer": "Wave three must not be the shortest impulse wave.",
                "topic": "elliott",
                "citation_ids": [f"kb:{document_id}:0"],
            }

            self.assertEqual(client.get("/api/v1/training/evaluation").status_code, 401)
            self.assertEqual(
                client.get(
                    "/api/v1/training/evaluation", headers=self._invalid_headers()
                ).status_code,
                401,
            )
            self.assertEqual(
                client.post("/api/v1/training/examples", json=payload).status_code,
                401,
            )

            example_id = self._create_example(client, owner_headers, document_id)
            readiness = client.get("/api/v1/training/evaluation", headers=owner_headers)
            self.assertEqual(readiness.status_code, 200)
            self.assertEqual(readiness.json()["total_examples"], 1)

            delete_example_id = self._create_example(client, owner_headers, document_id)
            self.assertEqual(
                client.delete(f"/api/v1/training/examples/{delete_example_id}").status_code,
                401,
            )
            self.assertEqual(
                client.delete(
                    f"/api/v1/training/examples/{delete_example_id}",
                    headers=self._invalid_headers(),
                ).status_code,
                401,
            )
            deleted = client.delete(
                f"/api/v1/training/examples/{delete_example_id}",
                headers=owner_headers,
            )
            self.assertEqual(deleted.status_code, 200)

            predictions = {
                "predictions": [{
                    "example_id": example_id,
                    "answer": payload["expected_answer"],
                    "citation_ids": payload["citation_ids"],
                }]
            }
            self.assertEqual(
                client.post(
                    "/api/v1/training/evaluation/predictions", json=predictions
                ).status_code,
                401,
            )
            self.assertEqual(
                client.post(
                    "/api/v1/training/evaluation/predictions",
                    json=predictions,
                    headers=self._invalid_headers(),
                ).status_code,
                401,
            )
            approved = client.post(
                f"/api/v1/training/examples/{example_id}/approve",
                headers=owner_headers,
            )
            self.assertEqual(approved.status_code, 200, approved.text)
            evaluated = client.post(
                "/api/v1/training/evaluation/predictions",
                json=predictions,
                headers=owner_headers,
            )
            self.assertEqual(evaluated.status_code, 200, evaluated.text)
            self.assertEqual(evaluated.json()["predictions_evaluated"], 1)


if __name__ == "__main__":
    unittest.main()
