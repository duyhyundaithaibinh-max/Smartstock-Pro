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
- [x] **SP-003 — Fibonacci giá và thời gian.** Đã bổ sung engine xác định hai pivot trái dấu gần nhất đã xác nhận; tính retracement, extension và time projection theo số nến giao dịch; API `/api/v1/analysis/fibonacci`; trả điểm neo, timestamp, tham số pivot, phương pháp và giới hạn. Có unit tests.
- [x] **SP-004 — Cấu trúc sóng Elliott dạng giả thuyết.** Đã bổ sung bộ đánh giá impulse 5 sóng từ sáu pivot luân phiên đã xác nhận; kiểm tra Wave 2, Wave 3, vùng chồng lấn Wave 4 và quy tắc Wave 3 không ngắn nhất; trả rule score, sóng, điều kiện xác nhận/vô hiệu và giới hạn. API `/api/v1/analysis/elliott`; có unit tests tăng/giảm và trường hợp vi phạm.
- [x] **SP-005 — Dòng tiền và tín hiệu tích lũy/phân phối.** Đã bổ sung CMF, ADL, OBV, up/down volume ratio, phân kỳ giá-volume và co hẹp volume; phân loại ứng viên tích lũy/phân phối theo điều kiện minh bạch. API `/api/v1/analysis/volume-flow`; có unit tests và giới hạn rõ ràng do chỉ có OHLCV.
- [x] **SP-006 — API tổng hợp báo cáo phân tích.** Đã bổ sung engine tổng hợp price action, Fibonacci, Elliott, volume flow và chỉ báo; tạo ba kịch bản tăng/cơ sở/giảm với điều kiện xác nhận/vô hiệu, nguồn dữ liệu và trạng thái điều chỉnh giá. API `/api/v1/analysis/report`; có unit tests.

### P1 — Android MVP

- [x] **SP-007 — Danh sách theo dõi.** SQLite watchlist, API GET/POST/DELETE/sắp xếp và unit tests; backend CI đã pass trong run 42388931745.
- [x] **SP-008 — Biểu đồ giá và khối lượng.** API `/api/v1/candles/chart`, engine tổng hợp OHLCV ngày/tuần/tháng, màn hình Flutter biểu đồ nến/khối lượng; backend tests, Flutter analyze/tests và build debug APK đều pass trong run 42388931745.
- [x] **SP-009 — Trang chi tiết mã.** Đã thêm engine `stock_detail`, API `/api/v1/symbols/{symbol}/detail` và màn hình Flutter gồm RSI/MACD/EMA/ATR, xu hướng, hỗ trợ/kháng cự, thanh khoản ước tính, nguồn/thời điểm dữ liệu; unit tests và CI backend/Android pass tại run 42389536702.
- [x] **SP-010 — Giao diện báo cáo kịch bản.** Đã thêm màn hình Flutter đọc `/api/v1/analysis/report`, hiển thị xu hướng, breakout, RSI và ba kịch bản cùng bằng chứng/điều kiện xác nhận-vô hiệu; ghi rõ đây là báo cáo quy tắc, chưa phải kết luận AI. Backend tests, Flutter analyze/tests và build debug APK pass tại run 42389536702.

### P2 — Hybrid AI và kiểm soát chất lượng

- [ ] **SP-011 — Model adapter độc lập nhà cung cấp.** Đang triển khai nền tảng `ModelAdapter`/`ModelGateway`: mặc định tắt, không có SDK hay kết nối mạng; chọn adapter qua cấu hình, kiểm tra ngân sách dự kiến, timeout và cô lập lỗi. Cần CI xác nhận trước khi đánh dấu hoàn thành.
- [ ] **SP-012 — AI chỉ diễn giải kết quả engine.** Không để mô hình tự bịa giá, volume, chỉ báo hoặc dữ liệu chưa có.
- [ ] **SP-013 — Bộ đánh giá chất lượng phân tích.** Golden test, kiểm tra tính nhất quán, kiểm thử hồi quy và lưu phiên bản quy tắc.

### P3 — Giai đoạn 2: Hybrid AI Training Room

- [ ] **SP-014 — Nhập tài liệu và quản lý knowledge base.**
- [ ] **SP-015 — RAG có trích dẫn nguồn và phân quyền dữ liệu.**
- [ ] **SP-016 — Quy tắc phân tích có phiên bản và lịch sử thay đổi.**
- [ ] **SP-017 — Bộ đánh giá, so sánh phiên bản và cải thiện quy tắc.**

## Quy tắc chọn việc

Chọn mục chưa hoàn thành có mã nhỏ nhất và ưu tiên cao nhất. Nếu mục đó bị chặn bởi thiếu dữ liệu, API, quyền hoặc quyết định sản phẩm, không tự đoán; ghi rõ blocker trong PR và chuyển sang mục tiếp theo chỉ khi không làm sai lệch thứ tự phụ thuộc.