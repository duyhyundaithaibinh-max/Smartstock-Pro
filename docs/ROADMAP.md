# Roadmap triển khai

## Đã triển khai trong backend MVP
- [x] FastAPI service, health endpoint.
- [x] SQLite schema cho mã và OHLCV, lưu provenance.
- [x] API tạo/tìm mã theo sàn.
- [x] CSV OHLCV import với kiểm tra định dạng và quan hệ OHLC.
- [x] SMA, EMA, RSI, MACD, ATR, OBV.
- [x] Unit tests và CI workflow.

## Tiếp theo
1. Adapter nhà cung cấp dữ liệu được cấp phép; đồng bộ tăng dần và retry.
2. Chuẩn hóa lịch giao dịch, corporate actions và dữ liệu điều chỉnh.
3. Mở rộng phân tích: Bollinger, stochastic, ADX, VWAP, Volume Profile.
4. Backtest có phí, trượt giá, survivorship-bias controls và walk-forward.
5. AI Training Room: tài liệu, versioning, RAG và bộ đánh giá.
6. Flutter Android: watchlist, chart, phân tích, danh mục.
7. Đóng gói Docker/backend và Android APK sau khi hoàn tất kiểm thử.

Không coi dữ liệu CSV do người dùng nhập là nguồn dữ liệu thị trường tự động.
