# Roadmap triển khai

## Đã có
- [x] FastAPI và health check.
- [x] SQLite cho mã và OHLCV, có nguồn dữ liệu.
- [x] Quản lý mã theo HOSE/HNX/UPCoM.
- [x] CSV import và kiểm tra OHLC.
- [x] SMA, EMA, RSI, MACD, ATR Wilder, OBV.
- [x] Bollinger Bands, cumulative VWAP, Stochastic, Volume Profile.
- [x] Unit tests, GitHub Actions.
- [x] Docker backend và Flutter dashboard skeleton.

## Còn phải hoàn thiện trước bản đóng gói phát hành
1. Chạy CI xanh trên commit cuối và kiểm thử tích hợp API/CSV.
2. Bổ sung data provider adapter hợp pháp, đồng bộ lịch sử/tự động, retry và lịch giao dịch.
3. Corporate actions, dữ liệu điều chỉnh và kiểm định dữ liệu.
4. Phân tích cấu trúc giá: swing/pivot, Fibonacci, Elliott có giải thích và mức độ tin cậy.
5. Backtest với phí, trượt giá, survivorship bias và walk-forward.
6. AI Training Room: tài liệu, versioning, RAG, đánh giá.
7. Flutter chart, watchlist, danh mục và cấu hình API an toàn.
8. Build Android APK, Docker image; kiểm thử cài đặt và hướng dẫn vận hành.

Không coi skeleton hiện tại là bản hoàn chỉnh hay khuyến nghị đầu tư.
