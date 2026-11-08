# Giáo trình 05 — Dữ liệu cổ phiếu Việt Nam và quản trị rủi ro

## Phạm vi thị trường
SmartStock Pro theo dõi cổ phiếu Việt Nam trên HOSE, HNX và UPCoM. Cần lưu mã, tên doanh nghiệp, sàn, ngành (nếu có), timeframe, dấu thời gian, OHLCV và nguồn dữ liệu. Không tự suy đoán sàn hoặc mã từ tên gần giống.

## Chất lượng dữ liệu
- Kiểm tra OHLC: high không thấp hơn open/close/low; low không cao hơn open/close/high; volume không âm.
- Phát hiện timestamp trùng, phiên thiếu, dữ liệu đảo thứ tự và giá trị ngoại lai.
- Lưu nguồn, thời điểm nhập, đơn vị và trạng thái điều chỉnh giá.
- Không tự điền phiên giao dịch bị thiếu.
- Nến tuần/tháng chỉ tổng hợp từ các nến ngày có sẵn; ghi rõ phương pháp tổng hợp.
- Giá × khối lượng chỉ là ước tính giá trị giao dịch từ OHLCV, không thay thế số liệu chính thức.

## Điều chỉnh giá và sự kiện doanh nghiệp
Cổ tức tiền mặt, cổ phiếu thưởng, phát hành quyền mua, chia tách/gộp và các sự kiện doanh nghiệp có thể làm thay đổi chuỗi giá. Trước khi phân tích dài hạn, cần xác minh nhà cung cấp đã điều chỉnh hay chưa. Không trộn dữ liệu điều chỉnh và chưa điều chỉnh trong cùng phép tính.

## Thanh khoản và rủi ro khớp lệnh
Giá trị giao dịch trung bình, độ sâu sổ lệnh, biên độ dao động, thanh khoản theo phiên và tình trạng hạn chế giao dịch ảnh hưởng khả năng thực hiện lệnh. Dữ liệu OHLCV lịch sử không đảm bảo có thể khớp tại giá đóng cửa.

## Quản trị rủi ro phân tích
Mỗi kịch bản cần có: luận điểm, điều kiện kích hoạt, mức vô hiệu, rủi ro gap/biên độ, thanh khoản, tỷ trọng rủi ro và thời điểm cập nhật. Không khuyến nghị mua/bán chỉ dựa trên một chỉ báo hoặc một nhãn sóng.

## Nguyên tắc báo cáo
- Phân biệt dữ liệu thật đã nhập, dữ liệu tính toán và giả thuyết.
- Ghi rõ ngày chốt dữ liệu và timeframe.
- Không tuyên bố realtime nếu nguồn không cấp quyền realtime.
- Không đưa ra lợi nhuận kỳ vọng như cam kết.
- Nêu thiếu sót dữ liệu có thể làm thay đổi kết luận.

## Câu hỏi kiểm tra
1. Vì sao phải xác minh trạng thái điều chỉnh giá?
2. Vì sao không tự sinh các phiên giao dịch bị thiếu?
3. Giá đóng cửa × khối lượng khác gì số liệu thanh khoản chính thức?
4. Một báo cáo kịch bản tối thiểu phải có điều kiện kích hoạt và vô hiệu nào?
