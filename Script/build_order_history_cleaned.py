"""Tao mot CSV sach theo tung don hang sau khi da tao cac bang FACT/DIM."""

import csv
import json
import re
from collections import defaultdict
from datetime import datetime
from decimal import Decimal
from pathlib import Path

from build_order_history_star import clean_text, item_parts


ROOT = Path(__file__).resolve().parent
STAR = ROOT / "order_history_star"
TARGET = ROOT / "order_history_cleaned.csv"

SPECIAL_NAMES = {
    "Restaurant ID": "SOURCE_RESTAURANT_ID", "Order ID": "SOURCE_ORDER_ID",
    "Customer ID": "SOURCE_CUSTOMER_ID", "Order Placed At": "ORDER_PLACED_AT_RAW",
    "Items in order": "ITEMS_IN_ORDER_RAW", "Rating": "RATING_VALUE",
    "KPT duration (minutes)": "KPT_MINUTES",
    "Rider wait time (minutes)": "RIDER_WAIT_MINUTES",
    "Restaurant discount (Promo)": "RESTAURANT_DISCOUNT_PROMO",
    "Restaurant discount (Flat offs, Freebies & others)": "RESTAURANT_DISCOUNT_OTHER",
    "Restaurant compensation (Cancellation)": "RESTAURANT_COMPENSATION_CANCELLATION",
    "Restaurant penalty (Rejection)": "RESTAURANT_PENALTY_REJECTION",
}
NUMBER_COLUMNS = [
    "BILL_SUBTOTAL", "PACKAGING_CHARGES", "RESTAURANT_DISCOUNT_PROMO",
    "RESTAURANT_DISCOUNT_OTHER", "GOLD_DISCOUNT", "BRAND_PACK_DISCOUNT",
    "TOTAL", "RESTAURANT_COMPENSATION_CANCELLATION",
    "RESTAURANT_PENALTY_REJECTION", "KPT_MINUTES", "RIDER_WAIT_MINUTES",
    "RATING_VALUE",
]


def read_csv(path):
    with path.open(encoding="utf-8-sig", newline="") as file:
        return list(csv.DictReader(file))


def column_name(name):
    return SPECIAL_NAMES.get(name, re.sub(r"[^A-Z0-9]+", "_", name.upper()).strip("_"))


def main():
    # Bước 2-3: Đọc dữ liệu gốc và các bảng đã tạo; kiểm tra số đơn.
    source = read_csv(ROOT / "order_history_kaggle_data.csv")
    facts = read_csv(STAR / "FACT_ORDER.csv")
    facts_by_order = {row["SOURCE_ORDER_ID"]: row for row in facts}
    assert len(source) == len(facts) == len(facts_by_order)

    dimensions = {}
    for name, keys in [("DATE", ["FULL_DATE"]), ("TIME", ["HOUR_NUMBER"]),
                       ("RESTAURANT", ["RESTAURANT_ID"]),
                       ("CUSTOMER", ["SOURCE_CUSTOMER_ID"]),
                       ("OUTCOME", ["OUTCOME_ID"]),
                       ("PROMOTION", ["DISCOUNT_CONSTRUCT"]), ("DISTANCE", ["DISTANCE"])]:
        dimensions[name] = (keys, {tuple(row[k] for k in keys): row
                                   for row in read_csv(STAR / f"DIM_{name}.csv")})

    items_by_order = defaultdict(list)
    for row in read_csv(STAR / "BRIDGE_ORDER_ITEM.csv"):
        items_by_order[row["SOURCE_ORDER_ID"]].append({
            "ITEM_NAME": row["ITEMS_IN_ORDER"],
            "ITEM_QUANTITY": int(row["ITEM_QUANTITY"]),
        })

    # Bước 5: Chuẩn hóa tên cột, chữ, số và ngày giờ; giữ lại chuỗi gốc.
    result = []
    for original in source:
        row = {column_name(name): clean_text(value) for name, value in original.items()}
        row["ORDER_PLACED_AT_RAW"] = original["Order Placed At"]
        row["ITEMS_IN_ORDER_RAW"] = original["Items in order"]

        fact = facts_by_order[row["SOURCE_ORDER_ID"]]
        assert Decimal(row["TOTAL"]) == Decimal(fact["TOTAL"])
        row.update(fact)
        for keys, rows in dimensions.values():
            row.update(rows[tuple(fact[k] for k in keys)])

        for name in NUMBER_COLUMNS:
            if row[name]:
                number = Decimal(row[name])
                precision = Decimal("0.1") if name == "RATING_VALUE" else Decimal("0.01")
                assert number.is_finite() and number == number.quantize(precision)
                row[name] = str(number.quantize(precision))

        placed_at = datetime.strptime(original["Order Placed At"], "%I:%M %p, %B %d %Y")
        row["ORDER_PLACED_AT"] = placed_at.strftime("%Y-%m-%d %H:%M:%S")
        row["ORDER_TIME"] = placed_at.strftime("%H:%M:%S")

        # Bước 5-6: Gộp món trùng và đối chiếu lại tổng tiền.
        items = items_by_order[fact["SOURCE_ORDER_ID"]]
        row["ITEMS_IN_ORDER_CLEANED"] = ", ".join(
            f"{item['ITEM_QUANTITY']} x {item['ITEM_NAME']}" for item in items)
        row["ITEMS_JSON"] = json.dumps(items, ensure_ascii=False, separators=(",", ":"))
        row["DISTINCT_ITEM_COUNT"] = len(items)
        row["TOTAL_ITEM_QUANTITY"] = sum(item["ITEM_QUANTITY"] for item in items)
        row["HAD_DUPLICATE_ITEMS"] = int(len(item_parts(original["Items in order"])) > len(items))

        discount = sum(Decimal(row[name]) for name in ["RESTAURANT_DISCOUNT_PROMO",
                                                     "RESTAURANT_DISCOUNT_OTHER",
                                                     "GOLD_DISCOUNT", "BRAND_PACK_DISCOUNT"])
        difference = Decimal(row["BILL_SUBTOTAL"]) + Decimal(row["PACKAGING_CHARGES"]) - discount - Decimal(row["TOTAL"])
        row["TOTAL_RECONCILIATION_DIFFERENCE"] = str(difference.quantize(Decimal("0.01")))
        row["HAS_TOTAL_DISCREPANCY"] = int(difference != 0)
        result.append(row)

    # Bước 7: Lưu một file CSV theo đơn hàng.
    with TARGET.open("w", encoding="utf-8-sig", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=list(result[0]), lineterminator="\r\n")
        writer.writeheader()
        writer.writerows(result)
    print(f"Da luu {len(result)} don hang vao {TARGET}")


if __name__ == "__main__":
    main()
