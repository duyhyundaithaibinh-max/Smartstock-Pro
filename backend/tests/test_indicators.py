import unittest
from app.indicators import sma, ema, rsi, macd, obv


class IndicatorTests(unittest.TestCase):
    def test_sma(self):
        self.assertEqual(sma([1, 2, 3, 4], 2), [None, 1.5, 2.5, 3.5])

    def test_ema_seed_and_length(self):
        result = ema([1, 2, 3, 4], 2)
        self.assertEqual(len(result), 4)
        self.assertIsNone(result[0])
        self.assertAlmostEqual(result[1], 1.5)

    def test_rsi_uptrend(self):
        result = rsi(list(range(1, 20)), 14)
        self.assertAlmostEqual(result[-1], 100.0)

    def test_macd_shape(self):
        result = macd([float(i) for i in range(1, 50)])
        self.assertEqual(len(result["macd"]), 49)
        self.assertEqual(len(result["histogram"]), 49)

    def test_obv(self):
        self.assertEqual(obv([10, 11, 10], [100, 200, 50]), [0, 200, 150])


if __name__ == "__main__":
    unittest.main()
