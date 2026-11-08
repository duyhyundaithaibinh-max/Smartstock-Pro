import os
import unittest
from unittest.mock import patch

from fastapi.requests import Request
from fastapi.responses import JSONResponse

from app.main import (
    api_token_is_valid,
    require_local_owner,
    validate_security_configuration,
)


class ApiSecurityTests(unittest.TestCase):
    def test_bearer_token_is_accepted(self):
        self.assertTrue(api_token_is_valid("Bearer correct-secret", "correct-secret"))

    def test_wrong_or_missing_token_is_rejected(self):
        self.assertFalse(api_token_is_valid("Bearer wrong-secret", "correct-secret"))
        self.assertFalse(api_token_is_valid(None, "correct-secret"))
        self.assertFalse(api_token_is_valid("Basic correct-secret", "correct-secret"))
        self.assertFalse(api_token_is_valid("Bearer ", "correct-secret"))

    def test_empty_expected_token_never_authorizes(self):
        self.assertFalse(api_token_is_valid("Bearer anything", ""))

    def test_production_allows_owner_session_without_legacy_api_token(self):
        validate_security_configuration("production", "")

    def test_development_can_run_without_api_token(self):
        validate_security_configuration("development", "")
        validate_security_configuration("test", "")

    def test_production_with_token_is_valid_configuration(self):
        validate_security_configuration("production", "long-random-secret-value-with-32chars")

    def test_short_token_is_rejected(self):
        with self.assertRaises(RuntimeError):
            validate_security_configuration("development", "too-short")

    def test_unicode_bearer_token_is_compared_safely(self):
        token = "mật-khẩu-rất-dài-để-kiểm-thử-1234567890"
        self.assertTrue(api_token_is_valid(f"Bearer {token}", token))


class ApiSecurityMiddlewareTests(unittest.IsolatedAsyncioTestCase):
    def make_request(self, path, method="GET", authorization=None):
        headers = []
        if authorization is not None:
            headers.append((b"authorization", authorization.encode("utf-8")))
        scope = {
            "type": "http",
            "asgi": {"version": "3.0"},
            "http_version": "1.1",
            "method": method,
            "scheme": "http",
            "path": path,
            "raw_path": path.encode("ascii"),
            "query_string": b"",
            "headers": headers,
            "server": ("testserver", 80),
            "client": ("testclient", 12345),
        }
        return Request(scope)

    async def call_next(self, request):
        return JSONResponse({"reached_route": True})

    async def invoke(self, request):
        with patch("app.main.auth.authenticate", return_value=None):
            return await require_local_owner(request, self.call_next)

    async def test_protected_write_rejects_missing_token(self):
        response = await self.invoke(self.make_request("/api/v1/symbols", "POST"))
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.headers["www-authenticate"], "Bearer")

    async def test_protected_write_rejects_invalid_token(self):
        with patch.dict(os.environ, {"SMARTSTOCK_API_TOKEN": "a" * 40}):
            response = await self.invoke(
                self.make_request("/api/v1/symbols", "POST", "Bearer " + "b" * 40)
            )
        self.assertEqual(response.status_code, 401)

    async def test_protected_write_accepts_legacy_shared_token(self):
        token = "c" * 40
        with patch.dict(os.environ, {"SMARTSTOCK_API_TOKEN": token}):
            response = await self.invoke(
                self.make_request("/api/v1/symbols", "POST", f"Bearer {token}")
            )
        self.assertEqual(response.status_code, 200)

    async def test_protected_write_accepts_authenticated_owner_session(self):
        with patch("app.main.auth.authenticate", return_value={
            "id": 1, "username": "owner", "role": "owner"
        }):
            response = await require_local_owner(
                self.make_request("/api/v1/symbols", "POST", "Bearer owner-session"),
                self.call_next,
            )
        self.assertEqual(response.status_code, 200)

    async def test_health_and_market_reads_remain_public(self):
        with patch.dict(os.environ, {"SMARTSTOCK_API_TOKEN": "d" * 40}):
            health = await self.invoke(self.make_request("/health"))
            markets = await self.invoke(self.make_request("/api/v1/markets"))
            symbols = await self.invoke(self.make_request("/api/v1/symbols"))
        self.assertEqual(health.status_code, 200)
        self.assertEqual(markets.status_code, 200)
        self.assertEqual(symbols.status_code, 200)

    async def test_auth_bootstrap_and_login_routes_remain_public_to_middleware(self):
        for path in (
            "/api/v1/auth/status",
            "/api/v1/auth/register-first-owner",
            "/api/v1/auth/login",
        ):
            response = await self.invoke(self.make_request(path, "POST"))
            self.assertEqual(response.status_code, 200, path)


if __name__ == "__main__":
    unittest.main()
