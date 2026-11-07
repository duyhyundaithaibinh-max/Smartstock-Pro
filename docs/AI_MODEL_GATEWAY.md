# SmartStock Pro — Model Gateway

## Mục tiêu

Tách lớp gọi mô hình khỏi logic phân tích kỹ thuật và khỏi nhà cung cấp. Các engine OHLCV, chỉ báo, price action, Fibonacci, Elliott, volume flow và báo cáo vẫn chạy độc lập; lỗi AI không được làm hỏng kết quả xác định.

## Trạng thái hiện tại

- `backend/app/model_adapter.py` định nghĩa `ModelRequest`, `ModelResponse`, giao kèo `ModelAdapter`, cấu hình và `ModelGateway`.
- Mặc định `enabled=false`, provider `none`, ngân sách mỗi yêu cầu bằng 0 USD.
- Chưa có adapter nhà cung cấp, SDK, khóa API hoặc lời gọi mạng.
- Gateway trả trạng thái `disabled` nếu chưa bật; không âm thầm gọi dịch vụ.
- Chỉ adapter được đăng ký rõ ràng và trùng tên provider mới được sử dụng.
- Có chặn trước theo chi phí ước tính, timeout, và cô lập exception của adapter.

## Ranh giới chi phí và độ tin cậy

1. Mặc định không phát sinh phí vì tính năng bị tắt và không có adapter mạng.
2. Ngân sách dựa trên chi phí ước tính do caller cung cấp; adapter cụ thể phải tự tính giá theo bảng giá hiện hành trước khi gửi request.
3. Gateway kiểm tra chi phí thực tế adapter báo về sau khi gọi. Đây là phát hiện vượt ngân sách, không thể thu hồi khoản phí đã phát sinh; không được coi là bảo đảm billing tuyệt đối.
4. Timeout ở gateway ngăn chờ vô hạn; adapter tích hợp thật cần hỗ trợ timeout ở tầng HTTP/SDK vì hủy chờ thread không nhất thiết dừng request đang chạy.
5. Không đưa API key vào source code, log, commit hoặc dữ liệu phân tích.
6. Không chuyển dữ liệu OHLCV hay tài liệu người dùng sang nhà cung cấp nếu chưa có quyền và cấu hình đồng ý riêng.

## Các trạng thái trả về

`disabled`, `not_configured`, `provider_mismatch`, `budget_blocked`, `timeout`, `provider_error`, `invalid_usage`, `cost_limit_exceeded`, `completed`.

## Bước kế tiếp

- SP-012: tạo lớp diễn giải chỉ nhận báo cáo định lượng đã tính; yêu cầu đầu ra có dẫn chứng và không được tự tạo số liệu.
- SP-013: golden tests và đánh giá hồi quy.
- Chỉ triển khai adapter thật sau khi người dùng chọn nhà cung cấp, xác nhận quyền dữ liệu và duyệt ngân sách.
