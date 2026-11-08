# Bộ giáo trình khởi tạo SmartStock Pro

Các tệp Markdown trong thư mục này là **tài liệu giáo dục do dự án biên soạn**, dùng làm nguồn nội bộ để khởi tạo Knowledge Base. Chúng không phải báo cáo khuyến nghị đầu tư, không đại diện cho dữ liệu giá thực tế và không thay thế sách/nghiên cứu gốc.

## Cách nạp vào Training Room
1. Mở Android → đăng nhập chủ sở hữu → Hybrid AI Training Room.
2. Chọn từng tệp Markdown trong thư mục này để tải lên.
3. Đặt nguồn là `internal_curriculum_v1` nếu trường nguồn được hiển thị; giữ nguyên tên tài liệu.
4. Tra cứu theo chủ đề, ghi lại `citation_id` thực tế do hệ thống trả về.
5. Tạo câu hỏi–đáp án dựa trên đúng nội dung trích dẫn; duyệt thủ công trước khi xuất JSONL.

Không tự điền citation ID giả định: ID phụ thuộc thứ tự tài liệu được nạp trong cơ sở dữ liệu.

## Thứ tự đề xuất
- 01 — Cấu trúc sóng Elliott và quy tắc vô hiệu.
- 02 — Fibonacci giá, vùng hợp lưu và Fibonacci thời gian.
- 03 — Chu kỳ thị trường và kiểm định thời gian.
- 04 — Khối lượng, dòng tiền và xác nhận breakout.
- 05 — Dữ liệu cổ phiếu Việt Nam, điều chỉnh giá và quản trị rủi ro.

## Nguyên tắc tạo dữ liệu chuẩn
- Mỗi câu trả lời phải gắn 1–10 citation ID có liên quan trực tiếp.
- Phân biệt quy tắc, giả thuyết, xác suất và kết luận đã xác nhận.
- Ghi rõ timeframe, dữ liệu đầu vào, ngày chốt dữ liệu và điều kiện vô hiệu khi nói về một mã cổ phiếu.
- Không biến một mô hình kỹ thuật thành lời hứa lợi nhuận.
- Giữ tập kiểm tra (holdout) riêng; không dùng cùng một ví dụ để vừa huấn luyện vừa tuyên bố đánh giá độc lập.

## Trạng thái
Đây là corpus khởi tạo. Sau khi nạp tài liệu, người dùng cần tạo và duyệt các ví dụ gắn citation. Tạo tài liệu không đồng nghĩa với huấn luyện/fine-tuning mô hình.
