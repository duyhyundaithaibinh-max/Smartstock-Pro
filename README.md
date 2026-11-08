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

## API security boundary

- Development mode keeps API authentication disabled for a local MVP. Do not expose this mode to an untrusted network.
- Enable shared Bearer-token protection by setting `SMARTSTOCK_API_TOKEN` in the environment. Android dashboard accepts the same token and sends it with API requests; the token remains in app memory and is not persisted.
- Production startup fails closed if `SMARTSTOCK_ENV=production` and `SMARTSTOCK_API_TOKEN` is missing.
- Example: copy `.env.example` to `.env`, generate a long random token, set `SMARTSTOCK_ENV=production` and `SMARTSTOCK_API_TOKEN`, then run Docker Compose.
- This is a single shared API token, **not** per-user authentication, role-based access control, or document-level ownership. Do not use it as a substitute for a proper account/permission system in a multi-user deployment. Use HTTPS/TLS at the trusted reverse proxy when accessing over a network; do not commit real secrets.

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

## Nguyên tắc
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
- The built-in `1.0.0` record preserves current defaults. Active configuration is applied by `/analysis/report` to Fibonacci lookback/pivot wing, Elliott lookback/pivot wing and volume-flow window; the report returns both rule version and configuration SHA-256. Price-action thresholds and indicator periods remain fixed defaults for now. API permission controls are not yet implemented.

## Rule version evaluation (SP-017 — foundation)
- `GET /api/v1/analysis/rules/compare?symbol=FPT&versions=1.0.0,1.1.0&timeframe=1d&limit=500` compares 2–5 stored rule versions against the same locally stored OHLCV candles.
- Output includes version/config hashes, input provenance, deterministic signatures (trend, breakout, Fibonacci, Elliott, volume-flow and scenario statuses) and only the fields that differ.
- This is an output comparison, not a backtest: no simulated fills, returns, win rate, forecast accuracy or claim that a newer version is better. Out-of-sample datasets and predeclared evaluation criteria are required for performance claims.

## Cài thử Android (APK debug)

1. Mở tab **Actions** của repository và chọn workflow run có commit cần thử; chỉ tải artifact `smartstock-pro-debug-apk` từ run có cả hai job `backend` và `android` thành công.
2. Tải ZIP artifact, giải nén và lấy file `app-debug.apk`.
3. Chuyển APK sang điện thoại Android, mở file và cho phép cài ứng dụng từ nguồn này nếu Android yêu cầu.
4. Mở SmartStock Pro. Trong ô **Backend URL**, nhập địa chỉ máy tính đang chạy backend cùng mạng Wi-Fi, ví dụ `http://192.168.1.10:8000`, rồi nhấn **Kết nối backend**.

### Kết nối điện thoại với backend

- Chạy backend trên máy tính và bind ra mạng LAN: `uvicorn app.main:app --host 0.0.0.0 --port 8000` (thực hiện trong thư mục `backend`).
- Nếu dùng Docker Compose, chạy `docker compose up --build -d`; bảo đảm cổng TCP 8000 được mở trong firewall của máy tính.
- Điện thoại và máy tính phải cùng mạng LAN/Wi-Fi. Thay địa chỉ ví dụ bằng IPv4 LAN thật của máy tính; không dùng `localhost` trên điện thoại. Địa chỉ `10.0.2.2` chỉ dành cho Android Emulator truy cập máy host.
- Kiểm tra từ trình duyệt điện thoại bằng `http://<IP-LAN-máy-tính>:8000/health` trước khi kết nối trong ứng dụng.

**Lưu ý bảo mật:** APK lấy từ CI hiện là bản debug để kiểm thử, không phải bản phát hành ký số. Cấu hình HTTP không mã hóa chỉ được bật cho debug build; không đưa backend thử nghiệm ra Internet công cộng. Trước khi phát hành rộng rãi cần cấu hình HTTPS, ký release APK/AAB, kiểm thử trên thiết bị thật và bổ sung hướng dẫn cập nhật/gỡ cài đặt.
