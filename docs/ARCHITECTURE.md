# SmartStock Pro — Kiến trúc MVP

## Mục tiêu
Ứng dụng Android phân tích HOSE, HNX, UPCoM; backend FastAPI; dữ liệu có nguồn gốc; AI hỗ trợ có kiểm soát.

## Các lớp
1. Mobile Flutter: watchlist, bảng giá, biểu đồ, phân tích, danh mục.
2. API FastAPI: mã chứng khoán, OHLCV, chỉ báo, phân tích.
3. Domain: chuẩn hóa mã, sàn, phiên giao dịch, nến và corporate actions.
4. Data adapters: mỗi nhà cung cấp một adapter riêng; chỉ tích hợp khi có quyền/API hợp lệ.
5. Storage: PostgreSQL; Redis tùy chọn; lưu tài liệu cho AI.
6. AI Training Room: nhập tài liệu, chunking, embeddings, RAG; quy tắc phân tích có phiên bản và đánh giá.

## Lộ trình
- P0: backend skeleton, health check, cấu hình, schema mã.
- P1: adapter OHLCV, đồng bộ lịch sử, kiểm tra chất lượng.
- P2: chỉ báo kỹ thuật và API biểu đồ.
- P3: watchlist/danh mục Android.
- P4: AI Training Room và RAG.
- P5: backtest, nhật ký tín hiệu, quản trị rủi ro.

## Quy tắc dữ liệu
Mỗi bản ghi giá gồm symbol, exchange, timeframe, timestamp, OHLCV, source, fetched_at và trạng thái kiểm định. Điều chỉnh giá/corporate actions có quy trình riêng; không âm thầm ghi đè dữ liệu nguồn.

## Loại trừ
Không xây VPS adapter, không phụ thuộc API/quyền truy cập VPS. Không tuyên bố dữ liệu real-time nếu nhà cung cấp không cấp quyền tương ứng.
