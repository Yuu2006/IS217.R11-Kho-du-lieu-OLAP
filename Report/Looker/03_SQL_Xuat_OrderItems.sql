-- Xuất FoodDelivery_OrderItems.csv cho Looker Studio: 1 dòng / cặp đơn–món (BRIDGE_ORDER_ITEM).
-- Không có cột tiền: tổng giá trị đơn phải lấy từ nguồn Orders.
SELECT
    b.FACT_ORDER_ID,
    i.ITEMS_IN_ORDER                                                      AS ItemName,
    b.ITEM_QUANTITY,
    d.YEAR_NUMBER                                                         AS YearNumber,
    d.MONTH_NUMBER                                                        AS MonthNumber,
    CONCAT(d.YEAR_NUMBER, '-', RIGHT('0' + CAST(d.MONTH_NUMBER AS varchar(2)), 2)) AS YearMonth,
    CASE WHEN d.IS_WEEKEND = 1 THEN N'Cuối tuần' ELSE N'Ngày thường' END  AS DayType,
    t.DAY_PART                                                            AS DayPart,
    r.RESTAURANT_NAME                                                     AS RestaurantName,
    r.SUBZONE                                                             AS Subzone
FROM BRIDGE_ORDER_ITEM b
JOIN DIM_ITEM       i ON i.ITEM_ID       = b.ITEM_ID
JOIN FACT_ORDER     f ON f.FACT_ORDER_ID = b.FACT_ORDER_ID
JOIN DIM_DATE       d ON d.DATE_ID       = f.DATE_ID
JOIN DIM_TIME       t ON t.TIME_ID       = f.TIME_ID
JOIN DIM_RESTAURANT r ON r.RESTAURANT_ID = f.RESTAURANT_ID
ORDER BY b.FACT_ORDER_ID, i.ITEMS_IN_ORDER;
