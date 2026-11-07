# SmartStock Pro — AI Developer tự động

## Mục tiêu

Dùng GitHub Actions + OpenAI Codex Action để thực hiện các đầu việc phát triển theo lịch hoặc theo yêu cầu, kiểm thử và mở Pull Request. Agent không commit trực tiếp lên `main`, không tự merge và không phát hành bản production.

## Luồng hoạt động

1. Workflow chạy theo lịch hằng ngày hoặc khi chủ repo bấm **Actions → SmartStock Pro AI Developer → Run workflow**.
2. Kiểm tra xem đã có Pull Request `ai-developer/*` đang mở chưa. Nếu có, bỏ qua lượt mới để tránh tạo thay đổi trùng lặp.
3. Chuẩn bị môi trường Python/Flutter và các dependency cần thiết trước khi chạy agent.
4. Codex đọc yêu cầu được nhập hoặc chọn một mục chưa hoàn thành trong `docs/AI_DEVELOPER_BACKLOG.md`, chỉnh sửa mã trong workspace.
5. Agent chỉ được phép sửa workspace trong sandbox; không có quyền ghi GitHub trong job chứa API key.
6. Workflow đóng gói phần thay đổi thành patch, chuyển sang job riêng không có API key.
7. Job kiểm thử lại backend và Android, build debug APK. Chỉ khi kiểm thử đạt mới mở Pull Request.
8. Chủ repo xem diff, CI và APK artifact rồi mới quyết định merge.

## Cấu hình bắt buộc một lần

Trong GitHub repository:

1. Mở **Settings → Secrets and variables → Actions**.
2. Chọn **New repository secret**.
3. Tên secret: `OPENAI_API_KEY`.
4. Giá trị: API key của OpenAI Platform. Không gửi key trong chat, issue, commit hoặc file cấu hình.
5. Kiểm tra tài khoản API có billing/credit phù hợp. API usage được tính phí riêng, không mặc định nằm trong gói ChatGPT.

Workflow chỉ dùng key trong bước Codex thông qua `openai/codex-action`; không truyền key cho bước checkout, build, test hay tạo Pull Request. Không cấp quyền ghi GitHub cho job có key.

## Kích hoạt và vận hành

- Lịch tự động: 09:00 giờ Việt Nam mỗi ngày.
- Chạy thủ công: tab **Actions** → **SmartStock Pro AI Developer** → **Run workflow**; có thể nhập một nhiệm vụ cụ thể.
- Nếu bỏ trống nhiệm vụ thủ công, agent lấy mục ưu tiên cao nhất chưa hoàn thành trong backlog.
- Nếu đã có PR của agent đang mở, lượt chạy mới sẽ bỏ qua.
- PR được tạo trên nhánh riêng dạng `ai-developer/task-<run_id>`.
- APK là debug build phục vụ thử nghiệm, không phải APK release đã ký.

## Ranh giới bảo mật

- Không tích hợp VPS dưới bất kỳ hình thức nào.
- Không tự merge PR, không ghi vào `main`, không tạo release production.
- Không được đọc hoặc in secrets; không thêm secrets vào mã nguồn.
- Không thay đổi workflow, quyền repo, cơ chế bảo vệ nhánh hoặc chính sách bảo mật.
- Không tải hoặc sử dụng dữ liệu thị trường trái điều khoản; không giả lập giá/khối lượng.
- Phân biệt dữ liệu thật, phép tính định lượng và diễn giải do AI tạo.
- Giới hạn mỗi lượt: một nhiệm vụ có phạm vi rõ ràng; không tự mở rộng sang thay đổi không liên quan.
- Nếu thiếu API key, thiếu quyền hoặc yêu cầu vượt phạm vi, dừng và ghi rõ việc cần chủ repo xử lý.

## Giới hạn hiện tại

Đây là pipeline agent chạy theo lịch/sự kiện trong GitHub Actions, không phải một tiến trình ChatGPT liên tục hoạt động 24/7. Mỗi lượt chạy là một phiên độc lập; trạng thái công việc được lưu trong GitHub backlog/PR. Chủ repo vẫn cần cấu hình API secret và duyệt PR.