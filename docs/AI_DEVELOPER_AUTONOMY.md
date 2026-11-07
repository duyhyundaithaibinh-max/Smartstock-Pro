# SmartStock Pro — Quy trình phát triển không phát sinh phí API

## Quyết định vận hành

Từ ngày 07/11/2026, dự án không sử dụng OpenAI API key hoặc Codex API trong GitHub Actions. Workflow AI Developer trước đây đã được gỡ khỏi nhánh phát triển để tránh lịch chạy tự động gọi dịch vụ có tính phí.

Không cần cấu hình `OPENAI_API_KEY` cho quy trình phát triển hiện tại. Không gửi API key vào repository, issue, commit hoặc cuộc trò chuyện.

## Cách phát triển

1. Người dùng trao đổi yêu cầu và thứ tự ưu tiên với ChatGPT.
2. ChatGPT hỗ trợ phân tích, thiết kế, viết và rà soát thay đổi theo từng nhiệm vụ.
3. Thay đổi được cập nhật lên nhánh riêng trong GitHub để review.
4. Chạy backend tests, Flutter analyze/tests và Android debug build bằng GitHub Actions trong hạn mức miễn phí của tài khoản.
5. Chỉ merge sau khi kiểm tra diff và kết quả CI.

## Phạm vi kỹ thuật

- Android trước; HOSE/HNX/UPCoM.
- Không tích hợp VPS.
- Không dùng dữ liệu giá/khối lượng giả lập.
- CSV là phương án nhập dữ liệu ban đầu; nguồn dữ liệu khác chỉ tích hợp khi có API và quyền sử dụng hợp pháp.
- Deterministic engine tính toán chỉ báo/vùng giá; AI chỉ diễn giải dữ liệu và kết quả có căn cứ.
- Không tự động merge hoặc phát hành production.

## Giới hạn cần hiểu rõ

- ChatGPT trong cuộc trò chuyện không chạy code nền liên tục khi người dùng rời phiên.
- GitHub Actions chỉ chạy các workflow kiểm thử/đóng gói được kích hoạt theo cấu hình; không có agent AI tự viết code định kỳ.
- GitHub Actions và artifact có hạn mức miễn phí theo gói; vượt hạn mức có thể phát sinh phí GitHub. Không có cam kết mọi khối lượng sử dụng đều miễn phí tuyệt đối.
- Các tính năng AI trong ứng dụng sau này cần model chạy cục bộ hoặc nhà cung cấp có phương án miễn phí phù hợp; không mặc định gọi API trả phí.

## Theo dõi tiến độ

Theo dõi các mục tại `docs/AI_DEVELOPER_BACKLOG.md`. Mỗi nhiệm vụ phải có thay đổi mã nguồn, kiểm thử và bằng chứng CI trước khi đánh dấu hoàn thành.
