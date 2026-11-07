# SmartStock Pro — AI Developer Backlog

Agent xử lý **một mục mỗi lượt chạy**, theo thứ tự ưu tiên. Khi hoàn thành, cập nhật trạng thái mục tương ứng trong cùng Pull Request và bổ sung test. Không đánh dấu Done nếu chưa có kiểm thử hoặc bằng chứng tương ứng.

## Nguyên tắc bắt buộc

- Android trước; thị trường HOSE/HNX/UPCoM.
- Không tích hợp VPS.
- Không dùng dữ liệu giá/khối lượng giả lập trong sản phẩm.
- Chỉ tích hợp nguồn dữ liệu có quyền/API hợp pháp; CSV là phương án nhập dữ liệu ban đầu.
- Engine tính toán xác định phải tách biệt với phần AI diễn giải.
- Không tự merge hoặc phát hành production.

## Công việc

### P0 — Hoàn thiện nền tảng phân tích MVP

- [x] **SP-001 — Kiểm tra hợp đồng dữ liệu OHLCV và chuẩn hóa dữ liệu.** Đã chuẩn hóa timestamp về Asia/Ho_Chi_Minh; chấp nhận ngày giao dịch YYYY-MM-DD, bắt buộc datetime có timezone; kiểm tra OHLC, số hữu hạn, volume không âm; từ chối timestamp trùng trong cùng file CSV; API nêu rõ trạng thái điều chỉnh giá là unknown, không tự suy đoán. Backend CI: 18 tests passed. 
- [x] **SP-002 — Xây dựng mô hình phân tích xu hướng và vùng giá.** Đã bổ sung engine xác định xu hướng bằng EMA20/EMA50, pivot support/resistance, breakout/breakdown theo biên ATR và xác nhận volume so với 20 nến trước; API `/api/v1/analysis/price-action`; trả điều kiện xác nhận/vô hiệu và giới hạn phương pháp. Có unit tests.
- [ ] **SP-003 — Fibonacci giá và thời gian.** Tính các mức giá/time ratio từ swing points được xác định; lưu đầu vào và phương pháp để kết quả có thể tái lập.
- [ ] **SP-004 — Cấu trúc sóng Elliott dạng giả thuyết.** Thiết kế nhiều kịch bản sóng, điều kiện xác nhận/vô hiệu và mức độ tin cậy; không khẳng định một cách đếm là sự thật tuyệt đối.
- [ ] **SP-005 — Dòng tiền và tín hiệu tích lũy/phân phối.** Bổ sung các phép tính có thể kiểm chứng từ OHLCV, ghi rõ giới hạn khi không có dữ liệu giao dịch chi tiết.
- [ ] **SP-006 — API tổng hợp báo cáo phân tích.** Trả về dữ liệu đầu vào, chỉ báo, vùng giá, kịch bản tăng/cơ sở/giảm và giải thích bằng chứng.

### P1 — Android MVP

- [ ] **SP-007 — Danh sách theo dõi.** Thêm watchlist có lưu trữ bền vững, sắp xếp và trạng thái dữ liệu.
- [ ] **SP-008 — Biểu đồ giá và khối lượng.** Biểu đồ OHLCV theo ngày/tuần/tháng, không hiển thị giá nếu backend chưa có dữ liệu.
- [ ] **SP-009 — Trang chi tiết mã.** Hiển thị chỉ báo, vùng hỗ trợ/kháng cự, thanh khoản và nguồn/thời điểm dữ liệu.
- [ ] **SP-010 — Giao diện AI Analysis.** Hiển thị ba kịch bản, điều kiện xác nhận/vô hiệu, bằng chứng và cảnh báo dữ liệu thiếu.

### P2 — Hybrid AI và kiểm soát chất lượng

- [ ] **SP-011 — Model adapter độc lập nhà cung cấp.** Không khóa kiến trúc vào một nhà cung cấp; quản lý timeout, lỗi, chi phí và cấu hình model.
- [ ] **SP-012 — AI chỉ diễn giải kết quả engine.** Không để mô hình tự bịa giá, volume, chỉ báo hoặc dữ liệu chưa có.
- [ ] **SP-013 — Bộ đánh giá chất lượng phân tích.** Golden test, kiểm tra tính nhất quán, kiểm thử hồi quy và lưu phiên bản quy tắc.

### P3 — Giai đoạn 2: Hybrid AI Training Room

- [ ] **SP-014 — Nhập tài liệu và quản lý knowledge base.**
- [ ] **SP-015 — RAG có trích dẫn nguồn và phân quyền dữ liệu.**
- [ ] **SP-016 — Quy tắc phân tích có phiên bản và lịch sử thay đổi.**
- [ ] **SP-017 — Bộ đánh giá, so sánh phiên bản và cải thiện quy tắc.**

## Quy tắc chọn việc

Chọn mục chưa hoàn thành có mã nhỏ nhất và ưu tiên cao nhất. Nếu mục đó bị chặn bởi thiếu dữ liệu, API, quyền hoặc quyết định sản phẩm, không tự đoán; ghi rõ blocker trong PR và chuyển sang mục tiếp theo chỉ khi không làm sai lệch thứ tự phụ thuộc.