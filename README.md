# IS217.R11 – Kho dữ liệu lịch sử đặt món (Food Delivery Order History)

Đồ án môn Kho dữ liệu và OLAP. Dữ liệu nguồn: 21.321 đơn hàng, từ 01/09/2024 đến 31/01/2025. Đi qua chuỗi sau:

```
CSV nguồn ──► SSIS ──► SQL Server (kho) ──► SSAS (cube) ──► Power BI  (kết nối trực tiếp tới cube)
                              │
                              └─► xuất CSV ──► Looker Studio
```

## Cấu trúc thư mục

| Thư mục | Nội dung |
|---|---|
| `Script/` | Script Python làm sạch và tạo star schema, 2 CSV nguồn cho SSIS (`dim_item_ssis.csv`, `bridge_order_item_ssis.csv`), `verify_ssis_load.sql` để kiểm tra sau khi nạp |
| `Schema/` | Thiết kế kho: `schema_sql_server.sql`, 15 truy vấn SQL và MDX, sơ đồ dbdiagram, CSV các bảng DIM/FACT. Xem `Schema/README.md` để biết mô hình chi tiết |
| `SSIS/` | Project SSIS (`Package.dtsx`): tạo bảng và nạp dữ liệu vào kho |
| `SSAS/` | Project SSAS Multidimensional: cube `Food Delivery Order History Data Ware House` |
| `Report/PowerBI/` | `FoodDelivery_Report.pbix`: 3 trang báo cáo, kết nối trực tiếp tới cube |
| `Report/Looker/` | SQL xuất dữ liệu, script xuất CSV, 2 CSV đã xuất, link báo cáo Looker Studio |

## Yêu cầu cài đặt

- **SQL Server** (project SSIS đặt `TargetServerVersion = SQLServer2025`) và **SSMS**.
- **SQL Server Analysis Services ở chế độ Multidimensional** (không phải Tabular). Chọn chế độ này khi cài, không đổi được sau khi cài.
- **Visual Studio** kèm 2 extension: *SQL Server Integration Services Projects* và *Microsoft Analysis Services Projects*. Các project dùng định dạng `.slnx`, nên cần Visual Studio bản mới hỗ trợ `.slnx`.
- **Power BI Desktop**.
- Tài khoản **Google** để dùng Looker Studio.
- **Python 3** (chỉ cần nếu chạy lại script ở Bước 0).
- Windows Authentication. Tất cả kết nối dưới đây dùng đăng nhập Windows, không có mật khẩu trong project.

> **Tên server:** project gốc dùng server `TUANVU`. Ở mọi chỗ ghi `TUANVU` bên dưới, hãy thay bằng tên máy bạn (hoặc `localhost`, hoặc `.`). Power BI và SSAS mặc định trỏ `localhost`.

---

## Bước 0. Chuẩn bị dữ liệu nguồn

Nguồn gốc là file Kaggle `order_history_kaggle_data.csv` (21.321 dòng). File này **không có trong repo**.

SSIS không đọc file Kaggle mà đọc 3 file CSV đã xử lý:

| File | Có trong repo? |
|---|---|
| `Script/dim_item_ssis.csv` (218 món) | Có |
| `Script/bridge_order_item_ssis.csv` (38.150 dòng) | Có |
| `order_history_ssis.csv` (21.321 đơn, 58 cột) | **Chưa có** (~16 MB) |

`order_history_ssis.csv` có 58 cột: 52 cột của `order_history_cleaned.csv` cộng 6 cột khóa `FACT_ORDER_ID`, `DATE_ID`, `TIME_ID`, `CUSTOMER_ID`, `PROMOTION_ID`, `DISTANCE_ID`. Script tạo ra file này chưa nằm trong repo. Cần có file này trước khi chạy SSIS.

Chạy lại phần star schema và `order_history_cleaned.csv` (không bắt buộc):

```powershell
# Đặt order_history_kaggle_data.csv cạnh các file .py, rồi:
cd Script
python build_order_history_star.py      # tạo thư mục order_history_star/ (11 CSV)
python build_order_history_cleaned.py   # tạo order_history_cleaned.csv (đọc order_history_star/)
```

Script ghi kết quả **cạnh chính nó**. Bản có sẵn của `order_history_star/` nằm ở `Schema/`.

## Bước 1. Tạo kho dữ liệu bằng SSIS

1. Trong SSMS, tạo database trống tên **`Food_Delivery_Order_History_DataWareHouse`**:
   ```sql
   CREATE DATABASE Food_Delivery_Order_History_DataWareHouse;
   ```
   Package chỉ tạo bảng, không tạo database.
2. Đặt 3 file CSV của Bước 0 vào **`D:\olap\output\`** (tạo thư mục nếu chưa có). Đây là đường dẫn cố định trong 3 Flat File connection manager của package:
   - `D:\olap\output\order_history_ssis.csv`
   - `D:\olap\output\dim_item_ssis.csv`
   - `D:\olap\output\bridge_order_item_ssis.csv`

   Nếu muốn để chỗ khác, sửa `ConnectionString` của 3 connection manager `Food_Delivery_Order_History_Source`, `ITEM_SOURCE`, `BRIDGE_ORDER_ITEM`.
3. Mở `SSIS/Food_Delivery_Order_History_SSIS/Food_Delivery_Order_History_SSIS.slnx` trong Visual Studio.
4. Mở `Package.dtsx`. Ở khung **Connection Managers** có 2 kết nối OLE DB tới `TUANVU` / `Food_Delivery_Order_History_DataWareHouse`. Sửa **Server name** thành server của bạn (cả 2 kết nối) rồi **Test Connection**.
5. Nếu Visual Studio báo lỗi về `ProtectionLevel`, đặt `ProtectionLevel = DontSaveSensitive` trong thuộc tính project và package. Project không có mật khẩu nào cần lưu.
6. Chạy package (**Start**). Package gồm các task `Drop All Tables`, `Create All Tables`, nạp 8 bảng DIM, nạp `FACT_ORDER` và `BRIDGE_ORDER_ITEM`. Package xóa bảng cũ trước khi tạo lại, nên chạy lại sẽ nạp lại từ đầu.
7. Kiểm tra: mở `Script/verify_ssis_load.sql` trong SSMS (chọn database kho) rồi chạy. Kết quả đúng:

   | Bảng | Số dòng |
   |---|---:|
   | DIM_DATE | 153 |
   | DIM_TIME | 18 |
   | DIM_RESTAURANT | 24 |
   | DIM_CUSTOMER | 11.607 |
   | DIM_OUTCOME | 34 |
   | DIM_PROMOTION | 528 |
   | DIM_DISTANCE | 22 |
   | DIM_ITEM | 218 |
   | FACT_ORDER | 21.321 |
   | BRIDGE_ORDER_ITEM | 38.150 |

   Cùng với `SUM(TOTAL) = 14.554.058,14`, 2.491 đơn có đánh giá, tổng 41.287 phần món, 0 dòng mồ côi, và 18 đơn lệch tổng 0,01 Rs (đúng như nguồn, không sửa).

> **Khác với `Schema/schema_sql_server.sql`:** bảng do SSIS tạo dùng khóa số (`DATE_ID`, `FACT_ORDER_ID`, ...). Còn `Schema/schema_sql_server.sql` và các CSV trong `Schema/` dùng khóa nguồn (`FULL_DATE`, `SOURCE_ORDER_ID`, ...). Cube SSAS và các SQL xuất cho Looker được viết cho **bảng do SSIS tạo**. Đừng trộn hai cách nạp trong cùng một database.

## Bước 2. Tạo cube bằng SSAS

1. Mở `SSAS/Food_Delivery_Order_History_SSAS/Food_Delivery_Order_History_SSAS.slnx` trong Visual Studio (project Multidimensional).
2. Trong **Solution Explorer → Data Sources**, mở `Food Delivery Order History Data Ware House.ds`. Sửa connection string: `Data Source=TUANVU` thành server của bạn, `Initial Catalog=Food_Delivery_Order_History_DataWareHouse`.
3. Tab **Impersonation Information**: project đang dùng *Use the service account*. Cấp quyền đọc kho cho tài khoản chạy dịch vụ Analysis Services. Với instance mặc định đó là `NT Service\MSOLAPService`:
   ```sql
   USE Food_Delivery_Order_History_DataWareHouse;
   CREATE USER [NT Service\MSOLAPService] FOR LOGIN [NT Service\MSOLAPService];
   ALTER ROLE db_datareader ADD MEMBER [NT Service\MSOLAPService];
   ```
   (Tạo LOGIN trước nếu chưa có.) Nếu không muốn cấp quyền, đổi sang *Use a specific Windows user name and password*.
4. Chuột phải project → **Properties → Deployment**. Đặt **Server = `localhost`** (hoặc tên instance SSAS của bạn) và **Database = `Food_Delivery_Order_History_SSAS`**. Cấu hình deploy lưu trong file `.user` nên không có trong repo.
5. **Build → Deploy Solution**. Quá trình này deploy rồi process Full. Cũng có thể chuột phải project, chọn **Process** sau khi deploy.
6. Kiểm tra: kết nối SSMS vào **Analysis Services**, mở MDX query trên database `Food_Delivery_Order_History_SSAS`, cube `Food Delivery Order History Data Ware House`. Chạy thử các câu trong `Schema/queries_mdx.mdx`.

Cube gồm các **measure**: `OrderCount`, `TotalAmount`, `SubtotalAmount`, `DiscountAmount`, `PackagingAmount`, `RatingSum`, `RatingCount`, `KptSum`, `KptCount`, `RiderWaitSum`, `RiderWaitCount`, `ItemQuantity`, `OrderItemCount`. Các **dimension** là `DIM CUSTOMER`, `DATE`, `DISTANCE`, `ITEM`, `ORDER`, `OUTCOME`, `PROMOTION`, `RESTAURANT`, `TIME`.

## Bước 3. Báo cáo Power BI

`Report/PowerBI/FoodDelivery_Report.pbix` **không chứa dữ liệu**. Nó kết nối trực tiếp (live) tới cube:

```
Data Source=localhost; Initial Catalog=Food_Delivery_Order_History_SSAS;
Cube="Food Delivery Order History Data Ware House"
```

1. Hoàn thành Bước 2 (cube đã deploy và process, dịch vụ Analysis Services đang chạy).
2. Mở file `.pbix` bằng Power BI Desktop. Nếu SSAS của bạn không ở `localhost`: **Transform data → Data source settings → Change Source** rồi sửa tên server.
3. Nếu hỏi quyền truy cập, chọn *Windows* → *Use my current credentials*.
4. Kiểm tra: các trang `R01_TongQuan`, `R02_NhaHang`, `R03_MonAn` hiện số liệu. Đối chiếu bảng số liệu ở cuối tài liệu.

Muốn dựng báo cáo mới từ đầu: **Get data → Analysis Services → Connect live**, nhập server và database, chọn cube.

## Bước 4. Báo cáo Looker Studio

### 4.1 Xuất 2 file CSV từ kho

Repo đã có sẵn 2 file (`FoodDelivery_Orders.csv`, 21.321 dòng; `FoodDelivery_OrderItems.csv`, 38.150 dòng). Chỉ chạy lại khi dữ liệu kho thay đổi:

```powershell
cd Report\Looker
.\05_Xuat_CSV_tu_kho.ps1 -Server localhost
```

Script chạy `02_SQL_Xuat_Orders.sql` (1 dòng/đơn, đọc `FACT_ORDER`) và `03_SQL_Xuat_OrderItems.sql` (1 dòng/cặp đơn–món). Tiền được `CAST` sang chuỗi trong SQL để không phụ thuộc định dạng số của Windows. `04_SQL_Doi_chieu.sql` dùng để đối chiếu số liệu.

### 4.2 Tạo 2 nguồn dữ liệu

Tại https://lookerstudio.google.com: **Tạo → Nguồn dữ liệu → Tải tệp CSV lên**, cấp phép, tạo tập dữ liệu mới, chọn file rồi bấm **Kết nối**. Làm lần lượt cho 2 file, đặt tên nguồn là `FoodDelivery_Orders` và `FoodDelivery_OrderItems`.

Chỉnh kiểu dữ liệu của `FoodDelivery_Orders`:
- `KPT_MINUTES`, `RATING_VALUE`: đổi sang **Số** (Looker nhận nhầm là Văn bản vì có ô trống).
- `TOTAL`, `BILL_SUBTOTAL`, `DISCOUNT_TOTAL`: phải là **Số**.
- `OrderDate`: để **Văn bản**.

Thêm các **trường đã tính** (Thêm trường → Thêm trường đã tính):

`FoodDelivery_Orders`

| Tên | Công thức |
|---|---|
| OrderCount | `COUNT(FACT_ORDER_ID)` |
| TotalAmount | `SUM(TOTAL)` |
| AverageOrderAmount | `SUM(TOTAL) / NULLIF(COUNT(FACT_ORDER_ID), 0)` |
| DiscountPercent | `100 * SUM(DISCOUNT_TOTAL) / NULLIF(SUM(BILL_SUBTOTAL), 0)` |
| RatingCount | `SUM(RatingPresent)` |
| AverageRating | `SUM(RATING_VALUE) / NULLIF(SUM(RatingPresent), 0)` |
| AverageKptMinutes | `SUM(KPT_MINUTES) / NULLIF(SUM(KptPresent), 0)` |

`FoodDelivery_OrderItems`

| Tên | Công thức |
|---|---|
| ItemQuantity | `SUM(ITEM_QUANTITY)` |
| OrderItemCount | `COUNT(FACT_ORDER_ID)` |
| AverageItemsPerOrder | `SUM(ITEM_QUANTITY) / NULLIF(COUNT_DISTINCT(FACT_ORDER_ID), 0)` |

Điểm trung bình và thời gian chuẩn bị trung bình chia cho số đơn **có ghi nhận** (`RatingPresent`, `KptPresent`), không chia cho tất cả đơn. Vì vậy mới cần 2 cột cờ này.

### 4.3 Dựng 3 báo cáo

Dùng khổ canvas **1200 × 1150** (**Giao diện và bố cục → Bố cục**) để đủ chỗ cho bảng Pivot. Mỗi báo cáo có tiêu đề, bộ lọc (thả xuống) và ít nhất 3 visual:

| Báo cáo | Nguồn | Nội dung |
|---|---|---|
| R01 Tổng quan | `FoodDelivery_Orders` | Thẻ số, biểu đồ, Pivot nhóm theo tháng và khu vực, có tổng phụ và tổng cộng |
| R02 Nhà hàng, khuyến mại, chất lượng | `FoodDelivery_Orders` | Theo nhà hàng, khu vực, loại khuyến mại; điểm đánh giá và thời gian chuẩn bị |
| R03 Món ăn và thời điểm đặt | `FoodDelivery_OrderItems` | Top món, theo khung giờ và loại ngày |

Link 3 báo cáo của nhóm nằm trong `Report/Looker/Links_LookerStudio.md`. Các báo cáo đang để riêng tư nên chỉ chủ sở hữu mở được.

---

## Số liệu đối chiếu

Số liệu ở kho, cube, Power BI và Looker phải khớp nhau:

| Chỉ số | Giá trị |
|---|---|
| Số đơn | 21.321 |
| Tổng giá trị đơn | 14.554.058,14 |
| Giá trị trung bình mỗi đơn | 682,62 |
| Tổng số phần món | 41.287 |
| Số cặp đơn–món | 38.150 |
| Điểm đánh giá trung bình (2.491 đơn có điểm) | 4,36 |
| Thời gian chuẩn bị trung bình (phút) | 17,33 |
| Tỷ lệ giảm giá | 13,34% |

## Lỗi thường gặp

| Hiện tượng | Cách xử lý |
|---|---|
| SSIS: `Cannot open database "Food_Delivery_Order_History_DataWareHouse"` | Chưa tạo database (Bước 1.1) hoặc sai tên server trong 2 kết nối OLE DB |
| SSIS: lỗi không thấy file CSV | File chưa nằm trong `D:\olap\output\` hoặc chưa sửa đường dẫn connection manager |
| SSAS: lỗi *OLE DB error … Login failed* khi Process | Chưa cấp quyền đọc kho cho tài khoản dịch vụ SSAS (Bước 2.3) |
| SSAS: không deploy được | Instance SSAS đang ở chế độ Tabular. Cần instance Multidimensional |
| Power BI: không kết nối được | Chưa process cube, dịch vụ Analysis Services chưa chạy, hoặc server không phải `localhost` |
| Looker: `Rating`/`KPT` hiện Văn bản, điểm trung bình sai | Chưa đổi `KPT_MINUTES` và `RATING_VALUE` sang Số (Bước 4.2) |
