import os
import unittest
from unittest.mock import patch

from fastapi.requests import Request
from fastapi.responses import JSONResponse

from app.main import (
    api_token_is_valid,
    protect_api_routes,
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

    def test_production_requires_api_token(self):
        with self.assertRaises(RuntimeError):
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
    def make_request(self, path, authorization=None):
        headers = []
        if authorization is not None:
            headers.append((b"authorization", authorization.encode("utf-8")))
        scope = {
            "type": "http",
            "asgi": {"version": "3.0"},
            "http_version": "1.1",
            "method": "GET",
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

    async def test_api_route_rejects_missing_token(self):
        with patch.dict(os.environ, {"SMARTSTOCK_API_TOKEN": "a" * 40}):
            response = await protect_api_routes(
                self.make_request("/api/v1/markets"), self.call_next
            )
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.headers["www-authenticate"], "Bearer")

    async def test_api_route_accepts_valid_token(self):
        token = "b" * 40
        with patch.dict(os.environ, {"SMARTSTOCK_API_TOKEN": token}):
            response = await protect_api_routes(
                self.make_request("/api/v1/markets", f"Bearer {token}"),
                self.call_next,
            )
        self.assertEqual(response.status_code, 200)

    async def test_health_route_remains_public_when_token_is_configured(self):
        with patch.dict(os.environ, {"SMARTSTOCK_API_TOKEN": "c" * 40}):
            response = await protect_api_routes(
                self.make_request("/health"), self.call_next
            )
        self.assertEqual(response.status_code, 200)

    async def test_api_route_remains_available_without_development_token(self):
        with patch.dict(os.environ, {}, clear=True):
            response = await protect_api_routes(
                self.make_request("/api/v1/markets"), self.call_next
            )
        self.assertEqual(response.status_code, 200)


if __name__ == "__main__":
    unittest.main()
