# Chạy 02/03_*.sql trên kho và ghi CSV UTF-8 (dấu phẩy ngăn cột, dấu chấm thập phân) cho Looker Studio.
param([string]$Server = 'localhost', [string]$Database = 'Food_Delivery_Order_History_DataWareHouse')
$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot
$jobs = @{ '02_SQL_Xuat_Orders.sql' = 'FoodDelivery_Orders.csv'; '03_SQL_Xuat_OrderItems.sql' = 'FoodDelivery_OrderItems.csv' }
$cn = New-Object System.Data.SqlClient.SqlConnection "Server=$Server;Database=$Database;Integrated Security=True;TrustServerCertificate=True"
$cn.Open()
try {
    foreach ($sql in $jobs.Keys) {
        $cmd = $cn.CreateCommand(); $cmd.CommandText = Get-Content (Join-Path $dir $sql) -Raw -Encoding UTF8
        $t = New-Object System.Data.DataTable; [void](New-Object System.Data.SqlClient.SqlDataAdapter $cmd).Fill($t)
        $out = Join-Path $dir $jobs[$sql]
        # số tiền đã CAST sang chuỗi trong SQL nên không phụ thuộc định dạng số của Windows
        $t | Select-Object ($t.Columns | ForEach-Object ColumnName) | Export-Csv $out -NoTypeInformation -Encoding utf8
        "{0}: {1} dòng" -f $jobs[$sql], $t.Rows.Count
    }
} finally { $cn.Close() }
