import math
import unittest
from datetime import datetime, timedelta, timezone

from pydantic import ValidationError

from app.schemas import Candle


class CandleContractTests(unittest.TestCase):
    def valid_payload(self, **overrides):
        payload = {
            "timestamp": "2026-11-07",
            "open": 10,
            "high": 12,
            "low": 9,
            "close": 11,
            "volume": 1000,
        }
        payload.update(overrides)
        return payload

    def test_date_only_is_exchange_local_vietnam_time(self):
        candle = Candle.model_validate(self.valid_payload())
        self.assertEqual(candle.timestamp.utcoffset(), timedelta(hours=7))
        self.assertEqual(candle.timestamp.isoformat(), "2026-11-07T00:00:00+07:00")

    def test_aware_timestamp_is_normalized_to_vietnam_time(self):
        candle = Candle.model_validate(self.valid_payload(timestamp="2026-11-06T17:00:00Z"))
        self.assertEqual(candle.timestamp.isoformat(), "2026-11-07T00:00:00+07:00")

    def test_naive_datetime_is_rejected(self):
        with self.assertRaises(ValidationError):
            Candle.model_validate(self.valid_payload(timestamp="2026-11-07T09:00:00"))

    def test_high_must_cover_open_close_and_low(self):
        for values in ({"high": 10}, {"high": 8}):
            with self.subTest(values=values), self.assertRaises(ValidationError):
                Candle.model_validate(self.valid_payload(**values))

    def test_low_must_not_exceed_open_or_close(self):
        with self.assertRaises(ValidationError):
            Candle.model_validate(self.valid_payload(low=11.5))

    def test_non_finite_ohlcv_is_rejected(self):
        for field in ("open", "high", "low", "close", "volume"):
            with self.subTest(field=field), self.assertRaises(ValidationError):
                Candle.model_validate(self.valid_payload(**{field: math.inf}))

    def test_negative_volume_is_rejected(self):
        with self.assertRaises(ValidationError):
            Candle.model_validate(self.valid_payload(volume=-1))

    def test_timezone_equivalent_instants_normalize_identically(self):
        a = Candle.model_validate(self.valid_payload(timestamp="2026-11-07T00:00:00+07:00"))
        b = Candle.model_validate(self.valid_payload(timestamp="2026-11-06T17:00:00Z"))
        self.assertEqual(a.timestamp.isoformat(), b.timestamp.isoformat())


if __name__ == "__main__":
    unittest.main()
