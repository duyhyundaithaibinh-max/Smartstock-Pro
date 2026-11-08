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
- [ ] **SP-015 — RAG có trích dẫn nguồn và phân quyền dữ liệu (đang triển khai).** Đã có BM25-style lexical retrieval cục bộ, citation ID ổn định, metadata nguồn/SHA-256/vị trí ký tự và context giới hạn 12.000 ký tự; nội dung tài liệu luôn là bằng chứng không đáng tin cậy, không phải chỉ thị. API tìm kiếm và resolver citation trả đúng chunk, offset và metadata; có kiểm thử no-evidence, xóa tài liệu và không lộ chunk trong danh sách. Đã thay lớp Bearer token dùng chung bằng xác thực chủ sở hữu cục bộ: mật khẩu PBKDF2-HMAC-SHA256 + salt, phiên token ngẫu nhiên chỉ lưu SHA-256, hết hạn 14 ngày và có thu hồi. **Giới hạn:** single-owner trên một backend cục bộ, chưa có nhiều tài khoản, RBAC hoặc quyền riêng theo tài liệu/nhóm; chưa có TLS/rate limit cho triển khai công khai. Chưa có embedding/semantic search hoặc LLM generation; không dùng API trả phí.
- [ ] **SP-016 — Quy tắc phân tích có phiên bản và lịch sử thay đổi (đang triển khai).** Đã có bảng SQLite append-only, semantic version MAJOR.MINOR.PATCH, canonical JSON + SHA-256, draft/active/archived, một phiên bản active duy nhất, kích hoạt phiên bản mới ghi một sự kiện append-only vào bảng `analysis_rule_activation_history`, gồm version, config SHA-256, phiên bản trước và thời điểm; có API `GET /api/v1/analysis/rules/history` phân trang, mới nhất trước. Migration tự ghi nhận phiên bản đang active hiện hữu làm mốc lịch sử đầu tiên. Baseline 1.0.0 được seed tự động. Cấu hình active đã được nối vào báo cáo cho price-action pivot lookback/wing, range lookback, ngưỡng volume xác nhận, ATR breakout buffer; Fibonacci lookback/pivot wing; Elliott lookback/pivot wing; volume-flow window; EMA nhanh/chậm được áp dụng đồng nhất cho engine xu hướng và chỉ báo, RSI, MACD nhanh/chậm/signal và ATR. Báo cáo xu hướng trả chu kỳ EMA thực tế và chỉ gắn alias EMA20/EMA50 khi đúng chu kỳ; SP-017 đưa cặp EMA xu hướng vào chữ ký so sánh và có regression tests. Báo cáo trả version + SHA-256. Chưa có phân quyền/ủy quyền API.
- [ ] **SP-017 — Bộ đánh giá, so sánh phiên bản và cải thiện quy tắc (đang triển khai).** Đã có hàm/API so sánh 2–5 phiên bản trên cùng một OHLCV, đối chiếu chữ ký đầu ra xu hướng/breakout/Fibonacci/Elliott/dòng tiền/kịch bản và tham số cấu hình; tách rõ `indicator_parameters` (chu kỳ cấu hình) khỏi `indicator_values` (giá trị tính trên OHLCV). Mỗi lượt so sánh trả SHA-256 fingerprint ổn định của toàn bộ chuỗi OHLCV có thứ tự (timestamp, OHLCV, source), giúp kiểm tra các phiên bản thực sự dùng cùng dữ liệu. Có regression tests cho fingerprint và phân tách tham số/kết quả. Không giả lập giao dịch hay tuyên bố lợi nhuận/độ chính xác; chưa có tập dữ liệu ngoài mẫu hoặc tiêu chí đánh giá hiệu năng.


- [ ] **SP-018 — Bộ dữ liệu huấn luyện có kiểm duyệt cho Training Room (đang triển khai).** Đã bổ sung bảng SQLite lưu câu hỏi/đáp án chuẩn/chủ đề/mã trích dẫn; API tạo/list/xóa/duyệt ví dụ, đánh giá độ sẵn sàng và xuất JSONL chỉ gồm ví dụ đã duyệt. Mọi ví dụ bắt buộc trỏ tới citation chunk đang tồn tại; xóa tài liệu nguồn sẽ khiến ví dụ không thể duyệt và không được xuất. Android Training Room có form tạo ví dụ, danh sách trạng thái, duyệt/xóa, chỉ số chất lượng và sao chép JSONL. Đây là chuẩn bị dữ liệu giám sát và kiểm định, **chưa phải fine-tuning hay chạy mô hình**.

- [ ] **SP-019 — Xác thực chủ sở hữu cục bộ (đang triển khai).** Chỉ cho phép tạo tài khoản chủ sở hữu đầu tiên; mật khẩu băm PBKDF2-HMAC-SHA256 với salt ngẫu nhiên; bearer session ngẫu nhiên, lưu hash SHA-256, hết hạn 14 ngày và thu hồi khi đăng xuất. Middleware bảo vệ các API ghi, watchlist, Knowledge Base, Training Room, quản lý quy tắc và đánh giá; GET thị trường/báo cáo kỹ thuật vẫn công khai. Android có màn hình khởi tạo/đăng nhập/đăng xuất và giữ token trong bộ nhớ, đóng ứng dụng cần đăng nhập lại. Đây là single-owner local, không phải multi-user/RBAC; chưa coi là an toàn để mở public Internet vì chưa có TLS/rate limit.
- [ ] **SP-020 — Giáo trình khởi tạo AI.** Đã bổ sung 5 tài liệu Markdown nội bộ về Elliott, Fibonacci, chu kỳ, volume/breakout và dữ liệu cổ phiếu Việt Nam/quản trị rủi ro, kèm bộ câu hỏi mẫu. Script `backend/scripts/ingest_curriculum.py` nạp tài liệu và tạo draft idempotent, citation ID lấy từ database thực tế; người dùng phải rà soát và duyệt từng ví dụ trong Training Room. Giáo trình nội bộ không phải nguồn giá thị trường hoặc khuyến nghị đầu tư.
- [ ] **SP-021 — Bộ đánh giá đầu ra mô hình cục bộ.** API nhận dự đoán do người dùng cung cấp và chấm trên ví dụ đã duyệt: exact match, token precision/recall/F1, độ bao phủ citation và citation ID không hợp lệ. Không tự gọi model, không fine-tune, không mạng/API trả phí. Token overlap không đánh giá đúng ngữ nghĩa; cần holdout set và con người kiểm duyệt trước khi kết luận chất lượng.
## Quy tắc chọn việc

Chọn mục chưa hoàn thành có mã nhỏ nhất và ưu tiên cao nhất. Nếu mục đó bị chặn bởi thiếu dữ liệu, API, quyền hoặc quyết định sản phẩm, không tự đoán; ghi rõ blocker trong PR và chuyển sang mục tiếp theo chỉ khi không làm sai lệch thứ tự phụ thuộc.

## Xác nhận CI và bản build Android (08/11/2026)
- PR #3, head commit `0e4ca186b9c6a51fe6e4a81ad4826a9737ecbb13`, workflow run `42431836190`: backend job **success** (111 tests); Android job **success** (Flutter analyze, Flutter tests, debug APK build và upload artifact).
- Artifact `smartstock-pro-debug-apk`, artifact ID `13598316184`; đã tải và xác minh ZIP chứa `app-debug.apk` (khoảng 150 MB). Đây là debug build để cài thử, chưa phải release ký số.
- CI này xác nhận chất lượng kiểm thử/build trên runner, không thay thế kiểm thử cài đặt trên thiết bị Android thực tế.
- PR vẫn mở, chưa merge. SP-015, SP-016, SP-017 vẫn là các nền tảng đang triển khai; không đánh dấu hoàn tất chỉ vì CI xanh.
