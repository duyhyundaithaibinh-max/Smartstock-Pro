# SmartStock Pro

Ứng dụng Android phân tích chứng khoán Việt Nam (HOSE/HNX/UPCoM), hướng tới dữ liệu minh bạch và AI hỗ trợ có kiểm soát.

## Backend MVP
- FastAPI API, SQLite schema cho mã và OHLCV.
- Nhập lịch sử nến ngày từ CSV, có kiểm tra OHLC và lưu nguồn dữ liệu.
- Chỉ báo: SMA, EMA, RSI, MACD, ATR (Wilder), OBV, Bollinger Bands, VWAP tích lũy, Stochastic và Volume Profile.
- Unit tests và GitHub Actions.
- Dockerfile và Docker Compose.

## Android MVP
Flutter dashboard kết nối backend và watchlist; có biểu đồ nến/khối lượng ngày-tuần-tháng và trang chi tiết mã hiển thị RSI, MACD, EMA, ATR, xu hướng, hỗ trợ/kháng cự, thanh khoản ước tính và chất lượng dữ liệu; có màn hình báo cáo ba kịch bản tăng/cơ sở/giảm với điều kiện xác nhận-vô hiệu. Chỉ có thể hiển thị mã đã nhập dữ liệu OHLCV hợp pháp. Báo cáo hiện tại là quy tắc kỹ thuật xác định, chưa gọi mô hình AI.

## Chạy backend local
```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```
Mở `http://127.0.0.1:8000/docs`.

## Chạy bằng Docker
Tại thư mục gốc: `docker compose up --build`. API ở `http://localhost:8000`.

## CSV OHLCV
Header: `timestamp,open,high,low,close,volume`. Tạo mã qua `POST /api/v1/symbols`, sau đó gọi `POST /api/v1/candles/import-csv?symbol=FPT&source=licensed-provider` và đính kèm file CSV.

## API phân tích và ứng dụng
- `GET /api/v1/analysis/price-action?symbol=FPT` — xu hướng, vùng giá, breakout.
- `GET /api/v1/analysis/fibonacci?symbol=FPT` — Fibonacci giá/thời gian.
- `GET /api/v1/analysis/elliott?symbol=FPT` — cấu trúc Elliott dạng giả thuyết.
- `GET /api/v1/analysis/volume-flow?symbol=FPT` — CMF/ADL/OBV và quan sát volume.
- `GET /api/v1/analysis/report?symbol=FPT` — báo cáo tổng hợp và ba kịch bản.
- `GET /api/v1/watchlist`, `POST /api/v1/watchlist?symbol=FPT`, `DELETE /api/v1/watchlist/FPT`, `PUT /api/v1/watchlist/order` — danh sách theo dõi.
- `GET /api/v1/candles/chart?symbol=FPT&period=weekly` — tổng hợp nến ngày/tuần/tháng từ dữ liệu ngày đã lưu.
- `GET /api/v1/symbols/FPT/detail` — snapshot chi tiết, chỉ báo, vùng giá, thanh khoản ước tính và nguồn.

Nến tuần/tháng chỉ tổng hợp từ các phiên ngày có sẵn; hệ thống không tự sinh phiên thiếu. Giá trị giao dịch `close × volume` chỉ là ước tính từ OHLCV, không thay thế số liệu thanh khoản chính thức.
\n## Nguyên tắc
- Không tích hợp VPS.
- Không giả lập dữ liệu giá.
- Chỉ kết nối nguồn dữ liệu khi có API/quyền sử dụng hợp pháp.
- Không công bố real-time nếu nhà cung cấp không cấp quyền tương ứng.
- Xác minh điều chỉnh giá/corporate actions trước khi phân tích dài hạn.


## Knowledge Base (SP-014)
- Upload: `POST /api/v1/knowledge/documents?source=research-note` (multipart field `file`; optional `title`).
- List: `GET /api/v1/knowledge/documents?limit=100&offset=0`.
- Detail and chunks: `GET /api/v1/knowledge/documents/{id}`.
- Delete: `DELETE /api/v1/knowledge/documents/{id}`.
- Supported formats: UTF-8 TXT/Markdown/CSV and text-based PDF; scanned PDFs requiring OCR are rejected explicitly.
- Local SQLite storage only; 10 MB upload cap, SHA-256 duplicate detection, deterministic 1,200-character chunks with 150-character overlap.
- Local retrieval: `GET /api/v1/knowledge/search?q=Fibonacci&top_k=5` — BM25-style lexical ranking, stable citation IDs, document provenance and bounded retrieval context. No embeddings, model calls or paid API; scanned PDFs still need OCR.

## Knowledge retrieval (SP-015 — foundation)
- Search indexed chunks: `GET /api/v1/knowledge/search?q=Elliott%20Wave&top_k=5`.
- Each hit returns a stable citation ID (`kb:document_id:chunk_index`), source filename/title, source label, SHA-256 and character offsets.
- The retrieval context is bounded to 12,000 characters and explicitly labels retrieved text as untrusted evidence; instructions embedded in source documents must not be followed.
- Current retrieval is deterministic BM25-style lexical matching, not semantic/vector search. It does not call an LLM or external service. Embeddings, model-backed generation and user/role-level document permissions remain future work.

## Versioned analysis rules (SP-016 — foundation)
- `GET /api/v1/analysis/rules` lists immutable rule versions and activation history.
- `GET /api/v1/analysis/rules/active` returns the active version and canonical JSON configuration.
- `POST /api/v1/analysis/rules` creates a draft using `{"version":"1.1.0","name":"EMA experiment","description":"Draft","config":{"trend":{"ema_fast":20}}}`.
- `POST /api/v1/analysis/rules/1.1.0/activate` activates an existing version and archives the prior active version.
- Versions use MAJOR.MINOR.PATCH, are append-only, and include a SHA-256 hash of canonical JSON configuration. Existing versions cannot be overwritten.
- The built-in `1.0.0` record is metadata for the current baseline. This registry does not yet change the analysis engine's calculation parameters; wiring validated configuration into engine modules and permission controls remains follow-up work. Keep this distinction explicit.
