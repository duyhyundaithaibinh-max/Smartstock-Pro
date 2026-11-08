# Giáo trình 02 — Fibonacci giá và thời gian

## Fibonacci thoái lui giá
Với một nhịp tăng từ đáy A đến đỉnh B, mức hồi được đo từ biên độ B−A. Các tỷ lệ thường quan sát gồm 23,6%, 38,2%, 50%, 61,8% và 78,6%. Mức 50% là tỷ lệ thị trường thường dùng, không phải tỷ lệ Fibonacci thuần túy. Với xu hướng giảm, phép đo đảo chiều theo nhịp giảm.

Các mức này là vùng quan sát phản ứng, không phải hỗ trợ/kháng cự chắc chắn. Cần xác định pivot A/B có ý nghĩa, cùng timeframe và cùng phương pháp điều chỉnh giá.

## Fibonacci mở rộng
Các mức mở rộng như 1,272; 1,618; 2,0 và 2,618 có thể dùng làm vùng mục tiêu tham khảo sau khi nhịp hồi hoàn tất. Không được chọn pivot sau khi đã biết kết quả chỉ để khớp một mục tiêu mong muốn.

## Hợp lưu
Độ tin cậy của vùng kỹ thuật có thể được đánh giá tốt hơn khi nhiều yếu tố độc lập hội tụ: Fibonacci, pivot cũ, hỗ trợ/kháng cự, đường trung bình, vùng tích lũy và cấu trúc khối lượng. Hợp lưu không đồng nghĩa các tín hiệu độc lập hoàn toàn; tránh đếm một yếu tố nhiều lần.

## Fibonacci thời gian
Fibonacci time projection thường dùng khoảng cách số nến giữa hai pivot để ước lượng các cửa sổ thời gian tiếp theo. Các khoảng thường khảo sát gồm 13, 21, 34, 55, 89 và 144 thanh nến. Đây là cửa sổ cần tăng cường quan sát, không phải ngày đảo chiều được bảo đảm.

Phải nêu rõ đơn vị thanh nến: ngày giao dịch, tuần hay tháng. Không trộn số ngày lịch với số phiên giao dịch. Nếu dùng chu kỳ tuần, cần so sánh cùng loại timeframe và xử lý ngày nghỉ/lịch giao dịch nhất quán.

## Quy trình
1. Chọn timeframe và pivot trước khi tính.
2. Ghi rõ nhịp đo và chiều xu hướng.
3. Tính vùng hồi/mở rộng; giữ nguyên các tỷ lệ đã định trước.
4. Tìm hợp lưu với cấu trúc giá và volume.
5. Chỉ nâng mức tin cậy khi có phản ứng giá xác nhận.
6. Ghi điều kiện vô hiệu nếu vùng bị xuyên thủng.

## Câu hỏi kiểm tra
1. Vì sao mức Fibonacci là vùng tham chiếu thay vì một mức giá chắc chắn?
2. Cần ghi những gì khi tính Fibonacci thời gian?
3. Hợp lưu kỹ thuật có thể bị đếm trùng tín hiệu như thế nào?
4. Vì sao không nên thay đổi pivot sau khi đã nhìn thấy kết quả?
