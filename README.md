# SmartStock Pro

Ứng dụng Android phân tích chứng khoán Việt Nam (HOSE/HNX/UPCoM), hướng tới dữ liệu minh bạch và AI hỗ trợ có kiểm soát.

## Backend MVP hiện có
- FastAPI health check và API danh sách sàn.
- Quản lý danh mục mã cổ phiếu.
- Lưu OHLCV bằng SQLite, có trường nguồn dữ liệu và thời điểm nhập.
- Nhập lịch sử nến ngày từ CSV do người dùng cung cấp.
- Tính SMA, EMA, RSI, MACD, ATR và OBV.
- Unit tests và GitHub Actions CI.

## Chạy local
```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```
Mở `http://127.0.0.1:8000/docs`.

## CSV OHLCV
Header bắt buộc: `timestamp,open,high,low,close,volume`.
Trước khi nhập, tạo mã qua `POST /api/v1/symbols`. Sau đó dùng `POST /api/v1/candles/import-csv?symbol=FPT&source=licensed-provider` với file CSV. Không có dữ liệu giá giả lập được cài sẵn.

## Nguyên tắc dữ liệu
- Chỉ kết nối nguồn dữ liệu khi có API/quyền sử dụng hợp pháp.
- Không tích hợp VPS.
- Dữ liệu real-time chỉ được công bố khi nhà cung cấp cấp quyền phù hợp.
- Cần xác minh điều chỉnh giá/corporate actions trước khi so sánh dài hạn.
