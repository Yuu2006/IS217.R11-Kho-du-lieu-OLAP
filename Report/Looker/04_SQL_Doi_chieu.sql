-- Số tổng để đối chiếu Power BI / Looker Studio với kho.
SELECT COUNT(*) AS OrderCount, SUM(TOTAL) AS TotalAmount,
       CAST(SUM(TOTAL) / COUNT(*) AS decimal(14,2)) AS AverageOrderAmount
FROM FACT_ORDER;

SELECT COUNT(*) AS OrderItemCount, SUM(ITEM_QUANTITY) AS ItemQuantity
FROM BRIDGE_ORDER_ITEM;

-- Theo tháng
SELECT d.YEAR_NUMBER, d.MONTH_NUMBER, COUNT(*) AS OrderCount, SUM(f.TOTAL) AS TotalAmount
FROM FACT_ORDER f JOIN DIM_DATE d ON d.DATE_ID = f.DATE_ID
GROUP BY d.YEAR_NUMBER, d.MONTH_NUMBER
ORDER BY d.YEAR_NUMBER, d.MONTH_NUMBER;

-- Theo nhà hàng (điểm TB chỉ tính đơn có đánh giá)
SELECT r.RESTAURANT_NAME, COUNT(*) AS OrderCount, SUM(f.TOTAL) AS TotalAmount,
       COUNT(f.RATING_VALUE) AS RatingCount,
       CAST(AVG(f.RATING_VALUE) AS decimal(4,2)) AS AverageRating
FROM FACT_ORDER f JOIN DIM_RESTAURANT r ON r.RESTAURANT_ID = f.RESTAURANT_ID
GROUP BY r.RESTAURANT_NAME
ORDER BY TotalAmount DESC;

-- Top 10 món theo số phần
SELECT TOP 10 i.ITEMS_IN_ORDER, SUM(b.ITEM_QUANTITY) AS ItemQuantity, COUNT(*) AS OrderItemCount
FROM BRIDGE_ORDER_ITEM b JOIN DIM_ITEM i ON i.ITEM_ID = b.ITEM_ID
GROUP BY i.ITEMS_IN_ORDER
ORDER BY ItemQuantity DESC;
