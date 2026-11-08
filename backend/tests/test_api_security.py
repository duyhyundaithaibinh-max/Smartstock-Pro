import unittest

from app.main import api_token_is_valid, validate_security_configuration


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


if __name__ == "__main__":
    unittest.main()
