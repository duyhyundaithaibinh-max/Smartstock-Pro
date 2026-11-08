# SmartStock Pro — Grounded AI Interpretation

## Mục tiêu

AI chỉ được diễn giải kết quả do các engine xác định tạo ra. AI không được tính lại hoặc tự phát sinh giá, khối lượng, chỉ báo, vùng hỗ trợ/kháng cự hay mục tiêu giá.

## Luồng dữ liệu

1. Engine hiện hữu tạo báo cáo kỹ thuật từ OHLCV đã lưu.
2. `build_interpretation_context(report)` chỉ xuất các facts được allow-list, mỗi fact có ID ổn định, giá trị và đường dẫn nguồn trong báo cáo.
3. Một model adapter tương lai chỉ nhận evidence packet này và yêu cầu trả về summary/claims có evidence IDs.
4. `validate_interpretation(context, proposal)` từ chối báo cáo không thành công, văn bản chứa token số tự do, claim không có dẫn chứng, evidence ID không tồn tại hoặc trùng lặp.
5. Ứng dụng hiển thị các giá trị định lượng bằng cách đọc `facts[evidence_id].value`, không lấy số từ câu văn của mô hình.

## Những điều không được coi là bảo đảm

- Đây là lớp kiểm tra cấu trúc và nguồn dẫn, không chứng minh ngữ nghĩa câu văn của AI luôn đúng.
- Evidence ID hợp lệ không đồng nghĩa câu văn diễn giải chính xác; cần SP-013 với golden tests và đánh giá con người.
- Hiện chưa gọi mô hình, chưa có adapter mạng, không phát sinh phí AI.
- Số liệu gốc vẫn phụ thuộc chất lượng, nguồn và trạng thái điều chỉnh của dữ liệu OHLCV; hiện trạng corporate action vẫn là unknown khi chưa xác minh.

## API nội bộ

- `build_interpretation_context(report)`: tạo gói bằng chứng cho model.
- `validate_interpretation(context, proposal)`: xác thực đầu ra có cấu trúc và trả lại facts gốc để UI render.
- Lỗi vi phạm trả về `InterpretationValidationError`; caller phải giữ nguyên báo cáo kỹ thuật xác định và không hiển thị nội dung AI bị từ chối.
