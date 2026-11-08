import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient

from app import auth, db
from app.main import app


class LocalAuthenticationTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.temp_dir.name) / "auth.db"
        self.patch_db = patch("app.db.DB_PATH", str(self.db_path))
        self.patch_db.start()
        db.init_db()

    def tearDown(self):
        self.patch_db.stop()
        self.temp_dir.cleanup()

    def test_first_owner_can_be_created_only_once(self):
        owner = auth.create_first_owner("owner_1", "a-long-test-password")
        self.assertEqual(owner, {"username": "owner_1", "role": "owner"})
        with self.assertRaises(auth.AuthError):
            auth.create_first_owner("owner_2", "another-long-password")

    def test_password_policy_and_username_validation(self):
        with self.assertRaises(auth.AuthError):
            auth.create_first_owner("ab", "short")
        with self.assertRaises(auth.AuthError):
            auth.create_first_owner("bad username", "a-long-test-password")

    def test_login_returns_opaque_token_and_logout_revokes_it(self):
        auth.create_first_owner("owner", "a-long-test-password")
        session = auth.login("owner", "a-long-test-password")
        token = session["access_token"]
        self.assertEqual(session["token_type"], "bearer")
        self.assertEqual(auth.authenticate(token)["username"], "owner")
        self.assertTrue(auth.revoke(token))
        self.assertIsNone(auth.authenticate(token))
        self.assertFalse(auth.revoke(token))

    def test_invalid_credentials_do_not_create_session(self):
        auth.create_first_owner("owner", "a-long-test-password")
        with self.assertRaises(auth.AuthError):
            auth.login("owner", "incorrect-password")
        with self.assertRaises(auth.AuthError):
            auth.login("missing", "incorrect-password")

    def test_expired_session_is_rejected(self):
        auth.create_first_owner("owner", "a-long-test-password")
        session = auth.login("owner", "a-long-test-password")
        with db.connection() as conn:
            conn.execute(
                "UPDATE auth_sessions SET expires_at='2000-01-01T00:00:00+00:00' WHERE token_sha256=?",
                (__import__("hashlib").sha256(session["access_token"].encode()).hexdigest(),),
            )
        self.assertIsNone(auth.authenticate(session["access_token"]))

    def test_private_api_requires_authentication(self):
        with TestClient(app) as client:
            response = client.get("/api/v1/training/examples")
            self.assertEqual(response.status_code, 401)
            self.assertEqual(response.headers.get("www-authenticate"), "Bearer")
            evaluation = client.post(
                "/api/v1/training/evaluation/predictions",
                json={"predictions": []},
            )
            self.assertEqual(evaluation.status_code, 401)

    def test_first_owner_setup_and_login_through_api(self):
        with TestClient(app) as client:
            setup = client.post("/api/v1/auth/register-first-owner", json={
                "username": "owner", "password": "a-long-test-password"
            })
            self.assertEqual(setup.status_code, 201)
            duplicate = client.post("/api/v1/auth/register-first-owner", json={
                "username": "second", "password": "another-long-password"
            })
            self.assertEqual(duplicate.status_code, 409)
            login = client.post("/api/v1/auth/login", json={
                "username": "owner", "password": "a-long-test-password"
            })
            self.assertEqual(login.status_code, 200)
            token = login.json()["access_token"]
            private = client.get("/api/v1/training/examples",
                                 headers={"Authorization": f"Bearer {token}"})
            self.assertEqual(private.status_code, 200)
            logout = client.post("/api/v1/auth/logout",
                                 headers={"Authorization": f"Bearer {token}"})
            self.assertEqual(logout.status_code, 200)
            after_logout = client.get("/api/v1/training/examples",
                                      headers={"Authorization": f"Bearer {token}"})
            self.assertEqual(after_logout.status_code, 401)

    def test_rule_management_is_not_in_public_market_read_allowlist(self):
        with TestClient(app) as client:
            response = client.get("/api/v1/analysis/rules")
            self.assertEqual(response.status_code, 401)

    def test_health_and_market_reads_remain_public(self):
        with TestClient(app) as client:
            health = client.get("/health")
            self.assertEqual(health.status_code, 200)
            self.assertEqual(health.json()["status"], "ok")
            self.assertEqual(client.get("/api/v1/markets").status_code, 200)
            self.assertEqual(client.get("/api/v1/symbols").status_code, 200)


if __name__ == "__main__":
    unittest.main()
