# SmartStock Pro

Ứng dụng Android phân tích chứng khoán Việt Nam (HOSE/HNX/UPCoM), hướng tới dữ liệu minh bạch và AI hỗ trợ có kiểm soát.

## Backend MVP
- FastAPI API, SQLite schema cho mã và OHLCV.
- Nhập lịch sử nến ngày từ CSV, có kiểm tra OHLC và lưu nguồn dữ liệu.
- Chỉ báo: SMA, EMA, RSI, MACD, ATR (Wilder), OBV, Bollinger Bands, VWAP tích lũy, Stochastic và Volume Profile.
- Unit tests và GitHub Actions.
- Dockerfile và Docker Compose.

## Android MVP
Flutter dashboard kết nối backend và watchlist; có biểu đồ nến/khối lượng ngày-tuần-tháng và trang chi tiết mã hiển thị RSI, MACD, EMA, ATR, xu hướng, hỗ trợ/kháng cự, thanh khoản ước tính và chất lượng dữ liệu. Chỉ có thể hiển thị mã đã nhập dữ liệu OHLCV hợp pháp.

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

## API phân tích và ứng dụng\n- `GET /api/v1/analysis/price-action?symbol=FPT` — xu hướng, vùng giá, breakout.\n- `GET /api/v1/analysis/fibonacci?symbol=FPT` — Fibonacci giá/thời gian.\n- `GET /api/v1/analysis/elliott?symbol=FPT` — cấu trúc Elliott dạng giả thuyết.\n- `GET /api/v1/analysis/volume-flow?symbol=FPT` — CMF/ADL/OBV và quan sát volume.\n- `GET /api/v1/analysis/report?symbol=FPT` — báo cáo tổng hợp và ba kịch bản.\n- `GET /api/v1/watchlist`, `POST /api/v1/watchlist?symbol=FPT`, `DELETE /api/v1/watchlist/FPT`, `PUT /api/v1/watchlist/order` — danh sách theo dõi.\n- `GET /api/v1/candles/chart?symbol=FPT&period=weekly` — tổng hợp nến ngày/tuần/tháng từ dữ liệu ngày đã lưu.\n- `GET /api/v1/symbols/FPT/detail` — snapshot chi tiết, chỉ báo, vùng giá, thanh khoản ước tính và nguồn.\n\nNến tuần/tháng chỉ tổng hợp từ các phiên ngày có sẵn; hệ thống không tự sinh phiên thiếu. Giá trị giao dịch `close × volume` chỉ là ước tính từ OHLCV, không thay thế số liệu thanh khoản chính thức.\n\n## Nguyên tắc
- Không tích hợp VPS.
- Không giả lập dữ liệu giá.
- Chỉ kết nối nguồn dữ liệu khi có API/quyền sử dụng hợp pháp.
- Không công bố real-time nếu nhà cung cấp không cấp quyền tương ứng.
- Xác minh điều chỉnh giá/corporate actions trước khi phân tích dài hạn.
