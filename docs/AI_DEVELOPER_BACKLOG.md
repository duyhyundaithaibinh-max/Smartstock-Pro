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
- [x] **SP-002 — Xây dựng mô hình phân tích xu hướng và vùng giá.** Đã bổ sung engine xác định xu hướng bằng EMA20/EMA50, pivot support/resistance, breakout/breakdown theo biên ATR và xác nhận volume; các tham số pivot lookback/wing, range lookback, ngưỡng volume và ATR buffer có thể cấu hình theo phiên bản quy tắc; API `/api/v1/analysis/price-action`; trả điều kiện xác nhận/vô hiệu và giới hạn phương pháp. Có unit tests.
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

- [x] **SP-011 — Model adapter độc lập nhà cung cấp.** Đã có `ModelAdapter`/`ModelGateway`, mặc định tắt, không có SDK hay kết nối mạng; chọn adapter qua cấu hình, kiểm tra ngân sách dự kiến, timeout và cô lập lỗi. Unit tests và CI backend/Android pass tại run 42390403719.
- [x] **SP-012 — AI chỉ diễn giải kết quả engine.** Đã thêm `interpretation_guard`: tạo allow-list facts từ báo cáo xác định, buộc từng nhận định trích evidence ID hợp lệ, từ chối số liệu tự do trong văn bản AI; chưa kết nối model. Backend/Android CI pass tại run 42392121818.
- [x] **SP-013 — Bộ đánh giá chất lượng phân tích.** Golden/regression tests trên fixture tổng hợp chỉ dùng trong unit test; kiểm tra tính xác định, thứ tự và hợp đồng kịch bản, tính nhất quán giữa báo cáo và evidence packet, không tự tạo chỉ báo khi thiếu dữ liệu, bảo toàn metadata nguồn/trạng thái điều chỉnh giá và phiên bản quy tắc. Evidence packet đã đưa rule version, source provenance và price-adjustment status vào allow-list; có unit tests cho một và nhiều nguồn dữ liệu. Backend CI run 42396336569: pass sau khi sửa fixture đa nguồn.

### P3 — Giai đoạn 2: Hybrid AI Training Room

- [x] **SP-014 — Nhập tài liệu và quản lý knowledge base.** API nhập TXT/Markdown/CSV/PDF dạng văn bản; trích xuất PDF bằng pypdf; SQLite metadata/chunks; SHA-256 chống nhập trùng; phân đoạn xác định 1.200 ký tự/overlap 150; list/detail/delete; giới hạn file 10 MB và văn bản trích xuất 2 triệu ký tự. PDF scan cần OCR bị từ chối rõ ràng. Backend unit tests pass tại CI run 42396336569; kiểm tra Android của PR đang tiếp tục. Chưa có embedding/RAG (SP-015).
- [ ] **SP-015 — RAG có trích dẫn nguồn và phân quyền dữ liệu (đang triển khai).** Đã có lớp truy xuất từ khóa BM25-style chạy local, xếp hạng chunk xác định, citation ID ổn định `kb:document_id:chunk_index`, metadata nguồn/SHA-256/vị trí ký tự và retrieval context giới hạn 12.000 ký tự. Context packet nay giữ nguyên document_id/chunk_id/chunk_index và char_start/char_end để lần ngược chính xác về đoạn nguồn. Nội dung tài liệu được đánh dấu là dữ liệu không đáng tin cậy, không phải chỉ thị. API `GET /api/v1/knowledge/search`; bổ sung kiểm thử hợp đồng API cho citation, source locator, no-evidence, xóa tài liệu và danh sách không lộ nội dung. Chưa có embedding/semantic search, LLM generation hoặc phân quyền người dùng/nhóm; chưa thể tuyên bố có phân quyền vì ứng dụng hiện chưa có identity/authentication. Không gọi dịch vụ trả phí.
- [ ] **SP-016 — Quy tắc phân tích có phiên bản và lịch sử thay đổi (đang triển khai).** Đã có bảng SQLite append-only, semantic version MAJOR.MINOR.PATCH, canonical JSON + SHA-256, draft/active/archived, một phiên bản active duy nhất, kích hoạt phiên bản mới lưu lịch sử và API list/active/create/activate. Baseline 1.0.0 được seed tự động. Cấu hình active được nối vào báo cáo cho price-action pivot lookback/wing, range lookback, ngưỡng volume xác nhận, ATR breakout buffer; Fibonacci lookback/pivot wing; Elliott lookback/pivot wing; volume-flow window; EMA nhanh/chậm áp dụng đồng nhất cho engine xu hướng và chỉ báo; RSI, MACD nhanh/chậm/signal và ATR. Trend report trả đúng EMA periods thực tế, không gắn nhãn EMA20/EMA50 khi cấu hình khác. Bộ so sánh SP-017 cũng đưa cặp EMA xu hướng vào chữ ký. Có regression test cho EMA tùy chỉnh. Chưa có phân quyền/ủy quyền API.
- [ ] **SP-017 — Bộ đánh giá, so sánh phiên bản và cải thiện quy tắc (đang triển khai).** Đã có hàm/API so sánh 2–5 phiên bản trên cùng một OHLCV, đối chiếu chữ ký đầu ra xu hướng/breakout/Fibonacci/Elliott/dòng tiền/kịch bản, trả các trường khác biệt và provenance đầu vào, bao gồm tham số breakout/pivot của price-action. Đã tách `indicator_parameters` (chu kỳ cấu hình) khỏi `indicator_values` (giá trị tính từ OHLCV) để tránh trộn cấu hình với kết quả; bổ sung regression test. Không giả lập giao dịch hay tuyên bố lợi nhuận/độ chính xác; chưa có tập dữ liệu ngoài mẫu hoặc tiêu chí đánh giá hiệu năng.

## Quy tắc chọn việc

Chọn mục chưa hoàn thành có mã nhỏ nhất và ưu tiên cao nhất. Nếu mục đó bị chặn bởi thiếu dữ liệu, API, quyền hoặc quyết định sản phẩm, không tự đoán; ghi rõ blocker trong PR và chuyển sang mục tiếp theo chỉ khi không làm sai lệch thứ tự phụ thuộc.

## Xác nhận CI và bản build Android (08/11/2026)
- PR #3, head commit `0e4ca186b9c6a51fe6e4a81ad4826a9737ecbb13`, workflow run `42431836190`: backend job **success** (111 tests); Android job **success** (Flutter analyze, Flutter tests, debug APK build và upload artifact).
- Artifact `smartstock-pro-debug-apk`, artifact ID `13598316184`; đã tải và xác minh ZIP chứa `app-debug.apk` (khoảng 150 MB). Đây là debug build để cài thử, chưa phải release ký số.
- CI này xác nhận chất lượng kiểm thử/build trên runner, không thay thế kiểm thử cài đặt trên thiết bị Android thực tế.
- PR vẫn mở, chưa merge. SP-015, SP-016, SP-017 vẫn là các nền tảng đang triển khai; không đánh dấu hoàn tất chỉ vì CI xanh.
