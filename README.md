# SmartStock Pro

Ứng dụng Android phân tích chứng khoán Việt Nam (HOSE/HNX/UPCoM), định hướng dữ liệu độc lập và AI hỗ trợ phân tích.

## Kiến trúc MVP
- `backend/`: Python FastAPI.
- `docs/`: đặc tả kiến trúc và lộ trình.
- `mobile/`: ứng dụng Flutter ở giai đoạn tiếp theo.

## Nguyên tắc
- Không tích hợp VPS.
- Không giả lập dữ liệu thị trường; dữ liệu mẫu phải được đánh dấu.
- Chỉ dùng nguồn dữ liệu hợp pháp, thay thế được qua adapter.
- Tín hiệu phân tích cần kiểm thử/backtest.

## Chạy backend
```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```
