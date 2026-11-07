import unittest
from app.indicators import sma,ema,rsi,macd,obv,atr,bollinger,vwap,stochastic,volume_profile

class IndicatorTests(unittest.TestCase):
    def test_sma(self): self.assertEqual(sma([1,2,3,4],2),[None,1.5,2.5,3.5])
    def test_ema(self):
        r=ema([1,2,3,4],2); self.assertIsNone(r[0]); self.assertAlmostEqual(r[1],1.5)
    def test_rsi(self): self.assertAlmostEqual(rsi(list(range(1,20)),14)[-1],100.0)
    def test_macd_shape(self):
        r=macd([float(i) for i in range(1,50)]); self.assertEqual(len(r["histogram"]),49)
    def test_obv(self): self.assertEqual(obv([10,11,10],[100,200,50]),[0,200,150])
    def test_atr_wilder_seed(self):
        r=atr([11,12,13],[9,10,11],[10,11,12],2); self.assertAlmostEqual(r[1],2.0)
    def test_bollinger(self):
        r=bollinger(list(range(1,22)),20); self.assertAlmostEqual(r["middle"][-1],11.5)
    def test_vwap(self): self.assertEqual(vwap([11,12],[9,10],[10,11],[100,100]),[10.0,10.5])
    def test_stochastic(self): self.assertEqual(len(stochastic([11,12,13],[9,10,11],[10,11,12],2,2)["d"]),3)
    def test_volume_profile(self):
        r=volume_profile([11,12],[9,10],[10,11],[100,200],4); self.assertEqual(r["total_volume"],300)

if __name__=="__main__": unittest.main()
