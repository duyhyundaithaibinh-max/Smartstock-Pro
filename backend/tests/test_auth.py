import hashlib
import logging
import os
import stat
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient

from app import auth, db
from app.main import app


class _CaptureHandler(logging.Handler):
    def __init__(self):
        super().__init__()
        self.messages = []

    def emit(self, record):
        self.messages.append(record.getMessage())


class LocalAuthenticationTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.temp_dir.name) / "auth.db"
        self.patch_db = patch("app.db.DB_PATH", str(self.db_path))
        self.patch_db.start()
        db.init_db()
        auth.ensure_bootstrap_secret()
        self.bootstrap_secret = auth.read_bootstrap_secret()

    def tearDown(self):
        self.patch_db.stop()
        self.temp_dir.cleanup()

    def _owner_count(self):
        with db.connection() as conn:
            return conn.execute("SELECT COUNT(*) FROM auth_users").fetchone()[0]

    def _bootstrap_row(self):
        with db.connection() as conn:
            return conn.execute(
                "SELECT secret_sha256, consumed_at FROM auth_bootstrap WHERE id=1"
            ).fetchone()

    def test_first_owner_can_be_created_only_once(self):
        owner = auth.create_first_owner("owner_1", "a-long-test-password", self.bootstrap_secret)
        self.assertEqual(owner, {"username": "owner_1", "role": "owner"})
        with self.assertRaises(auth.AuthError):
            auth.create_first_owner("owner_2", "another-long-password", self.bootstrap_secret)
        self.assertFalse(auth._bootstrap_secret_path().exists())

    def test_password_policy_and_username_validation(self):
        with self.assertRaises(auth.AuthError):
            auth.create_first_owner("ab", "short", self.bootstrap_secret)
        with self.assertRaises(auth.AuthError):
            auth.create_first_owner("bad username", "a-long-test-password", self.bootstrap_secret)

    def test_missing_and_wrong_bootstrap_secret_are_rejected_by_api(self):
        with TestClient(app) as client:
            missing = client.post("/api/v1/auth/register-first-owner", json={
                "username": "owner", "password": "a-long-test-password"
            })
            self.assertEqual(missing.status_code, 422)

            wrong = client.post("/api/v1/auth/register-first-owner", json={
                "username": "owner", "password": "a-long-test-password",
                "bootstrap_secret": "x" * 48,
            })
            self.assertEqual(wrong.status_code, 403)

        self.assertEqual(self._owner_count(), 0)
        self.assertIsNone(self._bootstrap_row()["consumed_at"])

    def test_consumed_bootstrap_secret_is_rejected_even_without_owner(self):
        with TestClient(app) as client:
            with db.connection() as conn:
                conn.execute(
                    "UPDATE auth_bootstrap SET consumed_at=CURRENT_TIMESTAMP WHERE id=1"
                )
            response = client.post("/api/v1/auth/register-first-owner", json={
                "username": "owner", "password": "a-long-test-password",
                "bootstrap_secret": self.bootstrap_secret,
            })
        self.assertEqual(response.status_code, 403)
        self.assertEqual(self._owner_count(), 0)

    def test_concurrent_first_owner_registration_consumes_secret_once(self):
        barrier = threading.Barrier(2)
        opened_connections = []
        opened_lock = threading.Lock()
        original_connect = db._connect

        def tracked_connect():
            conn = original_connect()
            with opened_lock:
                opened_connections.append(conn)
            return conn

        def register(username):
            barrier.wait(timeout=10)
            try:
                return auth.create_first_owner(
                    username, "a-long-test-password", self.bootstrap_secret
                )
            except auth.AuthError:
                return "rejected"

        with patch("app.db._connect", side_effect=tracked_connect):
            with ThreadPoolExecutor(max_workers=2) as pool:
                results = list(pool.map(register, ("owner_a", "owner_b")))

        self.assertEqual(sum(result != "rejected" for result in results), 1)
        self.assertEqual(results.count("rejected"), 1)
        self.assertEqual(len(opened_connections), 2)
        self.assertIsNot(opened_connections[0], opened_connections[1])
        self.assertEqual(self._owner_count(), 1)
        self.assertIsNotNone(self._bootstrap_row()["consumed_at"])

    def test_owner_insert_failure_rolls_back_secret_consumption(self):
        with db.connection() as conn:
            conn.execute("""
                CREATE TRIGGER fail_owner_insert
                BEFORE INSERT ON auth_users
                BEGIN
                    SELECT RAISE(ABORT, 'injected owner insert failure');
                END
            """)

        with self.assertRaises(Exception):
            auth.create_first_owner(
                "owner", "a-long-test-password", self.bootstrap_secret
            )

        self.assertEqual(self._owner_count(), 0)
        self.assertIsNone(self._bootstrap_row()["consumed_at"])
        self.assertEqual(
            self._bootstrap_row()["secret_sha256"],
            hashlib.sha256(self.bootstrap_secret.encode("utf-8")).hexdigest(),
        )

    @unittest.skipUnless(os.name == "posix", "POSIX file mode assertion")
    def test_bootstrap_secret_file_is_owner_only(self):
        secret_path = auth._bootstrap_secret_path()
        self.assertEqual(stat.S_IMODE(secret_path.stat().st_mode), 0o600)
        self.assertEqual(auth.read_bootstrap_secret(), self.bootstrap_secret)

    def test_missing_bootstrap_file_is_reported_and_repaired(self):
        secret_path = auth._bootstrap_secret_path()
        secret_path.unlink()
        with self.assertRaises(auth.AuthError):
            auth.read_bootstrap_secret()
        self.assertTrue(auth.ensure_bootstrap_secret())
        repaired = auth.read_bootstrap_secret()
        self.assertGreaterEqual(len(repaired), 32)
        self.assertNotEqual(repaired, self.bootstrap_secret)

    def test_invalid_empty_bootstrap_file_is_rotated(self):
        secret_path = auth._bootstrap_secret_path()
        secret_path.write_text("\n", encoding="utf-8")
        with self.assertRaises(auth.AuthError):
            auth.read_bootstrap_secret()
        self.assertTrue(auth.ensure_bootstrap_secret())
        self.assertTrue(auth.read_bootstrap_secret())

    @unittest.skipUnless(os.name == "posix", "POSIX permission assertion")
    def test_insecure_bootstrap_file_permissions_are_rejected_and_repaired(self):
        secret_path = auth._bootstrap_secret_path()
        secret_path.chmod(0o644)
        with self.assertRaises(auth.AuthError):
            auth.read_bootstrap_secret()
        self.assertTrue(auth.ensure_bootstrap_secret())
        self.assertEqual(stat.S_IMODE(secret_path.stat().st_mode), 0o600)
        self.assertNotEqual(auth.read_bootstrap_secret(), self.bootstrap_secret)

    def test_bootstrap_secret_is_not_returned_or_logged_by_setup_api(self):
        handler = _CaptureHandler()
        root_logger = logging.getLogger()
        root_logger.addHandler(handler)
        try:
            with TestClient(app) as client:
                response = client.post("/api/v1/auth/register-first-owner", json={
                    "username": "owner", "password": "a-long-test-password",
                    "bootstrap_secret": self.bootstrap_secret,
                })
        finally:
            root_logger.removeHandler(handler)

        self.assertEqual(response.status_code, 201)
        self.assertNotIn(self.bootstrap_secret, response.text)
        self.assertNotIn(self.bootstrap_secret, "\n".join(handler.messages))
        self.assertFalse(auth._bootstrap_secret_path().exists())

    def test_login_returns_opaque_token_and_logout_revokes_it(self):
        auth.create_first_owner("owner", "a-long-test-password", self.bootstrap_secret)
        session = auth.login("owner", "a-long-test-password")
        token = session["access_token"]
        self.assertEqual(session["token_type"], "bearer")
        self.assertEqual(auth.authenticate(token)["username"], "owner")
        self.assertTrue(auth.revoke(token))
        self.assertIsNone(auth.authenticate(token))
        self.assertFalse(auth.revoke(token))

    def test_invalid_credentials_do_not_create_session(self):
        auth.create_first_owner("owner", "a-long-test-password", self.bootstrap_secret)
        with self.assertRaises(auth.AuthError):
            auth.login("owner", "incorrect-password")
        with self.assertRaises(auth.AuthError):
            auth.login("missing", "incorrect-password")

    def test_expired_session_is_rejected(self):
        auth.create_first_owner("owner", "a-long-test-password", self.bootstrap_secret)
        session = auth.login("owner", "a-long-test-password")
        with db.connection() as conn:
            conn.execute(
                "UPDATE auth_sessions SET expires_at='2000-01-01T00:00:00+00:00' WHERE token_sha256=?",
                (hashlib.sha256(session["access_token"].encode()).hexdigest(),),
            )
        self.assertIsNone(auth.authenticate(session["access_token"]))

    def test_private_api_requires_authentication_and_owner_session_protects_write(self):
        with TestClient(app) as client:
            response = client.get("/api/v1/training/evaluation/predictions")
            self.assertEqual(response.status_code, 405)
            unauthorized = client.post("/api/v1/symbols", json={
                "symbol": "FPT", "name": "FPT", "exchange": "HOSE"
            })
            self.assertEqual(unauthorized.status_code, 401)
            evaluation = client.post(
                "/api/v1/training/evaluation/predictions",
                json={"predictions": []},
            )
            self.assertEqual(evaluation.status_code, 401)

            setup = client.post("/api/v1/auth/register-first-owner", json={
                "username": "owner", "password": "a-long-test-password",
                "bootstrap_secret": self.bootstrap_secret,
            })
            self.assertEqual(setup.status_code, 201)
            login = client.post("/api/v1/auth/login", json={
                "username": "owner", "password": "a-long-test-password"
            })
            self.assertEqual(login.status_code, 200)
            token = login.json()["access_token"]
            headers = {"Authorization": f"Bearer {token}"}
            created = client.post("/api/v1/symbols", json={
                "symbol": "FPT", "name": "FPT", "exchange": "HOSE"
            }, headers=headers)
            self.assertEqual(created.status_code, 201)
            private = client.get("/api/v1/training/evaluation/predictions", headers=headers)
            self.assertEqual(private.status_code, 405)
            logout = client.post("/api/v1/auth/logout", headers=headers)
            self.assertEqual(logout.status_code, 200)
            after_logout = client.post("/api/v1/symbols", json={
                "symbol": "HPG", "name": "HPG", "exchange": "HOSE"
            }, headers=headers)
            self.assertEqual(after_logout.status_code, 401)

    def test_legacy_shared_token_can_write_but_invalid_owner_token_cannot(self):
        token = "legacy-shared-token-" + "x" * 32
        with patch.dict(os.environ, {"SMARTSTOCK_API_TOKEN": token}):
            with TestClient(app) as client:
                accepted = client.post("/api/v1/symbols", json={
                    "symbol": "VNM", "name": "VNM", "exchange": "HOSE"
                }, headers={"Authorization": f"Bearer {token}"})
                self.assertEqual(accepted.status_code, 201)
                rejected = client.post("/api/v1/symbols", json={
                    "symbol": "VIC", "name": "VIC", "exchange": "HOSE"
                }, headers={"Authorization": "Bearer " + "z" * 48})
                self.assertEqual(rejected.status_code, 401)

    def test_rule_management_is_not_in_public_market_read_allowlist(self):
        with TestClient(app) as client:
            response = client.get("/api/v1/analysis/rules")
            self.assertEqual(response.status_code, 401)

    def test_market_read_endpoints_remain_public(self):
        with TestClient(app) as client:
            self.assertEqual(client.get("/api/v1/markets").status_code, 200)
            self.assertEqual(client.get("/api/v1/symbols").status_code, 200)


if __name__ == "__main__":
    unittest.main()
