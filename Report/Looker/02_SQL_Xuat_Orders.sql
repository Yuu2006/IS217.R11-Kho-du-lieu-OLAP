-- Xuất FoodDelivery_Orders.csv cho Looker Studio: 1 dòng / đơn (FACT_ORDER), không nối BRIDGE để tiền không bị nhân.
-- Database: Food_Delivery_Order_History_DataWareHouse
SELECT
    f.FACT_ORDER_ID,
    CONVERT(char(10), d.FULL_DATE, 23)                                    AS OrderDate,
    d.YEAR_NUMBER                                                         AS YearNumber,
    d.MONTH_NUMBER                                                        AS MonthNumber,
    CONCAT(d.YEAR_NUMBER, '-', RIGHT('0' + CAST(d.MONTH_NUMBER AS varchar(2)), 2)) AS YearMonth,
    CASE WHEN d.IS_WEEKEND = 1 THEN N'Cuối tuần' ELSE N'Ngày thường' END  AS DayType,
    t.DAY_PART                                                            AS DayPart,
    r.RESTAURANT_NAME                                                     AS RestaurantName,
    r.SUBZONE                                                             AS Subzone,
    r.CITY                                                                AS City,
    p.PROMOTION_TYPE                                                      AS PromotionType,
    o.ORDER_STATUS                                                        AS OrderStatus,
    CAST(f.BILL_SUBTOTAL  AS varchar(20))                                 AS BILL_SUBTOTAL,
    CAST(f.DISCOUNT_TOTAL AS varchar(20))                                 AS DISCOUNT_TOTAL,
    CAST(f.TOTAL          AS varchar(20))                                 AS TOTAL,
    CAST(f.RATING_VALUE   AS varchar(10))                                 AS RATING_VALUE,
    CAST(f.KPT_MINUTES    AS varchar(10))                                 AS KPT_MINUTES,
    CASE WHEN f.RATING_VALUE IS NULL THEN 0 ELSE 1 END                    AS RatingPresent,
    CASE WHEN f.KPT_MINUTES  IS NULL THEN 0 ELSE 1 END                    AS KptPresent
FROM FACT_ORDER f
JOIN DIM_DATE       d ON d.DATE_ID       = f.DATE_ID
JOIN DIM_TIME       t ON t.TIME_ID       = f.TIME_ID
JOIN DIM_RESTAURANT r ON r.RESTAURANT_ID = f.RESTAURANT_ID
JOIN DIM_PROMOTION  p ON p.PROMOTION_ID  = f.PROMOTION_ID
JOIN DIM_OUTCOME    o ON o.OUTCOME_ID    = f.OUTCOME_ID
ORDER BY f.FACT_ORDER_ID;
