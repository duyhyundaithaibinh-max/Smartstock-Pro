import unittest

from app.main import api_token_is_valid, validate_security_configuration


class ApiTokenValidationTests(unittest.TestCase):
    def test_accepts_valid_bearer_token(self):
        self.assertTrue(api_token_is_valid("Bearer secret-token", "secret-token"))

    def test_bearer_scheme_is_case_insensitive(self):
        self.assertTrue(api_token_is_valid("bEaReR secret-token", "secret-token"))

    def test_rejects_missing_authorization_header(self):
        self.assertFalse(api_token_is_valid(None, "secret-token"))

    def test_rejects_wrong_scheme(self):
        self.assertFalse(api_token_is_valid("Basic secret-token", "secret-token"))

    def test_rejects_wrong_token(self):
        self.assertFalse(api_token_is_valid("Bearer wrong-token", "secret-token"))

    def test_rejects_empty_expected_token(self):
        self.assertFalse(api_token_is_valid("Bearer secret-token", ""))

    def test_production_allows_owner_session_without_legacy_api_token(self):
        validate_security_configuration("production", "")

    def test_production_accepts_configured_api_token(self):
        validate_security_configuration("production", "long-random-secret-value-with-32chars")

    def test_development_allows_token_to_remain_unconfigured(self):
        validate_security_configuration("development", "")


if __name__ == "__main__":
    unittest.main()
