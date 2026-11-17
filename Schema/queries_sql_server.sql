-- 15 câu truy vấn phân tích lịch sử đơn hàng (SQL Server).
-- FACT_ORDER: mỗi dòng là một đơn hàng.
-- BRIDGE_ORDER_ITEM: mỗi dòng là một cặp đơn hàng - món ăn; ITEM_QUANTITY là số phần.
-- Các truy vấn có thể chạy riêng từng câu.

-- 01. Số đơn và tổng giá trị đơn hàng từng tháng thay đổi thế nào?
SELECT d.YEAR_NUMBER, d.MONTH_NUMBER,
       COUNT(*) AS so_don,
       SUM(f.TOTAL) AS tong_gia_tri_don_rs
FROM FACT_ORDER AS f
JOIN DIM_DATE AS d ON d.FULL_DATE = f.FULL_DATE
GROUP BY d.YEAR_NUMBER, d.MONTH_NUMBER
ORDER BY d.YEAR_NUMBER, d.MONTH_NUMBER;

-- 02. Từng khu vực có bao nhiêu đơn và tổng giá trị theo tháng?
SELECT d.YEAR_NUMBER, d.MONTH_NUMBER, r.SUBZONE,
       COUNT(*) AS so_don,
       SUM(f.TOTAL) AS tong_gia_tri_don_rs
FROM FACT_ORDER AS f
JOIN DIM_DATE AS d ON d.FULL_DATE = f.FULL_DATE
JOIN DIM_RESTAURANT AS r ON r.RESTAURANT_ID = f.RESTAURANT_ID
GROUP BY d.YEAR_NUMBER, d.MONTH_NUMBER, r.SUBZONE
ORDER BY d.YEAR_NUMBER, d.MONTH_NUMBER, r.SUBZONE;

-- 03. 10 món ăn được đặt nhiều nhất là món gì?
SELECT TOP (10) i.ITEMS_IN_ORDER,
       SUM(b.ITEM_QUANTITY) AS so_phan,
       COUNT(*) AS so_don_co_mon
FROM BRIDGE_ORDER_ITEM AS b
JOIN DIM_ITEM AS i ON i.ITEMS_IN_ORDER = b.ITEMS_IN_ORDER
GROUP BY i.ITEMS_IN_ORDER
ORDER BY so_phan DESC, i.ITEMS_IN_ORDER;

-- 04. Nhà hàng có tổng giá trị đơn lớn nhất là nhà hàng nào?
-- Các địa điểm cùng tên nhà hàng được cộng chung.
SELECT TOP (1) r.RESTAURANT_NAME,
       COUNT(*) AS so_don,
       SUM(f.TOTAL) AS tong_gia_tri_don_rs
FROM FACT_ORDER AS f
JOIN DIM_RESTAURANT AS r ON r.RESTAURANT_ID = f.RESTAURANT_ID
GROUP BY r.RESTAURANT_NAME
ORDER BY tong_gia_tri_don_rs DESC, r.RESTAURANT_NAME;

-- 05. Mỗi tháng, một đơn trung bình đặt bao nhiêu phần?
SELECT d.YEAR_NUMBER, d.MONTH_NUMBER,
       SUM(b.ITEM_QUANTITY) AS tong_so_phan,
       COUNT(DISTINCT f.SOURCE_ORDER_ID) AS so_don,
       1.0 * SUM(b.ITEM_QUANTITY) /
           NULLIF(COUNT(DISTINCT f.SOURCE_ORDER_ID), 0) AS so_phan_trung_binh_moi_don
FROM FACT_ORDER AS f
JOIN BRIDGE_ORDER_ITEM AS b ON b.SOURCE_ORDER_ID = f.SOURCE_ORDER_ID
JOIN DIM_DATE AS d ON d.FULL_DATE = f.FULL_DATE
GROUP BY d.YEAR_NUMBER, d.MONTH_NUMBER
ORDER BY d.YEAR_NUMBER, d.MONTH_NUMBER;

-- 06. Số đơn đã giao và từ chối thay đổi theo tháng ra sao?
SELECT d.YEAR_NUMBER, d.MONTH_NUMBER, o.ORDER_STATUS,
       COUNT(*) AS so_don
FROM FACT_ORDER AS f
JOIN DIM_DATE AS d ON d.FULL_DATE = f.FULL_DATE
JOIN DIM_OUTCOME AS o ON o.OUTCOME_ID = f.OUTCOME_ID
WHERE o.ORDER_STATUS IN (N'Delivered', N'Rejected')
GROUP BY d.YEAR_NUMBER, d.MONTH_NUMBER, o.ORDER_STATUS
ORDER BY d.YEAR_NUMBER, d.MONTH_NUMBER, o.ORDER_STATUS;

-- 07. Mỗi loại khuyến mãi có bao nhiêu đơn và tổng mức giảm chiếm bao nhiêu
--     phần trăm tiền tạm tính?
SELECT p.PROMOTION_TYPE,
       COUNT(*) AS so_don,
       SUM(f.DISCOUNT_TOTAL) AS tong_giam_gia_rs,
       SUM(f.BILL_SUBTOTAL) AS tong_tien_tam_tinh_rs,
       100.0 * SUM(f.DISCOUNT_TOTAL) /
           NULLIF(SUM(f.BILL_SUBTOTAL), 0) AS ty_le_giam_phan_tram
FROM FACT_ORDER AS f
JOIN DIM_PROMOTION AS p ON p.DISCOUNT_CONSTRUCT = f.DISCOUNT_CONSTRUCT
GROUP BY p.PROMOTION_TYPE
ORDER BY so_don DESC, p.PROMOTION_TYPE;

-- 08. TOP 3 nhà hàng có tổng phí đóng gói cao nhất?
-- Các địa điểm cùng tên nhà hàng được cộng chung.
SELECT TOP (3) r.RESTAURANT_NAME,
       SUM(f.PACKAGING_CHARGES) AS tong_phi_dong_goi_rs
FROM FACT_ORDER AS f
JOIN DIM_RESTAURANT AS r ON r.RESTAURANT_ID = f.RESTAURANT_ID
GROUP BY r.RESTAURANT_NAME
ORDER BY tong_phi_dong_goi_rs DESC, r.RESTAURANT_NAME;

-- 09. Điểm đánh giá trung bình của các đơn đã đánh giá theo nhà hàng?
SELECT r.RESTAURANT_NAME,
       COUNT(*) AS so_don_da_danh_gia,
       AVG(f.RATING_VALUE) AS diem_trung_binh
FROM FACT_ORDER AS f
JOIN DIM_RESTAURANT AS r ON r.RESTAURANT_ID = f.RESTAURANT_ID
WHERE f.RATING_VALUE IS NOT NULL
GROUP BY r.RESTAURANT_NAME
ORDER BY diem_trung_binh DESC, so_don_da_danh_gia DESC, r.RESTAURANT_NAME;

-- 10. Mỗi khu vực phát sinh những loại khiếu nại nào và bao nhiêu đơn?
SELECT r.SUBZONE, o.CUSTOMER_COMPLAINT_TAG,
       COUNT(*) AS so_don_khieu_nai
FROM FACT_ORDER AS f
JOIN DIM_RESTAURANT AS r ON r.RESTAURANT_ID = f.RESTAURANT_ID
JOIN DIM_OUTCOME AS o ON o.OUTCOME_ID = f.OUTCOME_ID
WHERE o.CUSTOMER_COMPLAINT_TAG <> N'Not recorded'
GROUP BY r.SUBZONE, o.CUSTOMER_COMPLAINT_TAG
ORDER BY r.SUBZONE, so_don_khieu_nai DESC, o.CUSTOMER_COMPLAINT_TAG;

-- 11. Thời gian chuẩn bị món trung bình theo từng khu vực là bao nhiêu?
SELECT r.SUBZONE,
       COUNT(f.KPT_MINUTES) AS so_don_co_thoi_gian,
       AVG(f.KPT_MINUTES) AS thoi_gian_chuan_bi_trung_binh_phut
FROM FACT_ORDER AS f
JOIN DIM_RESTAURANT AS r ON r.RESTAURANT_ID = f.RESTAURANT_ID
GROUP BY r.SUBZONE
ORDER BY r.SUBZONE;

-- 12. Thời gian tài xế chờ trung bình theo từng khoảng cách giao hàng là bao nhiêu?
SELECT x.DISTANCE,
       COUNT(f.RIDER_WAIT_MINUTES) AS so_don_co_thoi_gian,
       AVG(f.RIDER_WAIT_MINUTES) AS thoi_gian_cho_trung_binh_phut
FROM FACT_ORDER AS f
JOIN DIM_DISTANCE AS x ON x.DISTANCE = f.DISTANCE
GROUP BY x.DISTANCE, x.DISTANCE_INT
ORDER BY x.DISTANCE_INT, x.DISTANCE;

-- 13. TOP 3 khách quay lại có tổng giá trị đơn cao nhất?
SELECT TOP (3) c.SOURCE_CUSTOMER_ID,
       COUNT(*) AS so_don,
       SUM(f.TOTAL) AS tong_gia_tri_don_rs
FROM FACT_ORDER AS f
JOIN DIM_CUSTOMER AS c ON c.SOURCE_CUSTOMER_ID = f.SOURCE_CUSTOMER_ID
GROUP BY c.SOURCE_CUSTOMER_ID
HAVING COUNT(*) >= 2
ORDER BY tong_gia_tri_don_rs DESC, c.SOURCE_CUSTOMER_ID;

-- 14. Buổi nào trong ngày có số lượng đơn nhiều nhất, phân biệt giữa
--     ngày thường và cuối tuần?
WITH so_don_theo_buoi AS (
    SELECT d.IS_WEEKEND, t.DAY_PART,
           COUNT(*) AS so_don
    FROM FACT_ORDER AS f
    JOIN DIM_DATE AS d ON d.FULL_DATE = f.FULL_DATE
    JOIN DIM_TIME AS t ON t.HOUR_NUMBER = f.HOUR_NUMBER
    GROUP BY d.IS_WEEKEND, t.DAY_PART
),
xep_hang AS (
    SELECT IS_WEEKEND, DAY_PART, so_don,
           DENSE_RANK() OVER (
               PARTITION BY IS_WEEKEND ORDER BY so_don DESC
           ) AS hang
    FROM so_don_theo_buoi
)
SELECT CASE WHEN IS_WEEKEND = 1 THEN N'Cuối tuần'
            ELSE N'Ngày thường' END AS loai_ngay,
       DAY_PART AS buoi_trong_ngay,
       so_don
FROM xep_hang
WHERE hang = 1
ORDER BY IS_WEEKEND, DAY_PART;

-- 15. 10 món được đặt nhiều nhất vào cuối tuần?
SELECT TOP (10) i.ITEMS_IN_ORDER,
       SUM(b.ITEM_QUANTITY) AS so_phan,
       COUNT(*) AS so_don_co_mon
FROM BRIDGE_ORDER_ITEM AS b
JOIN FACT_ORDER AS f ON f.SOURCE_ORDER_ID = b.SOURCE_ORDER_ID
JOIN DIM_ITEM AS i ON i.ITEMS_IN_ORDER = b.ITEMS_IN_ORDER
JOIN DIM_DATE AS d ON d.FULL_DATE = f.FULL_DATE
WHERE d.IS_WEEKEND = 1
GROUP BY i.ITEMS_IN_ORDER
ORDER BY so_phan DESC, i.ITEMS_IN_ORDER;
