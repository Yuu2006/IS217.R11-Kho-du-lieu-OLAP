"""Build an order-grain FACT_ORDER and a many-to-many item bridge.

Run from any directory: python build_order_history_star.py
The source file is never modified. Outputs are UTF-8 CSV files in output/order_history_star.
"""

import csv
import re
import unicodedata
from collections import Counter, defaultdict
from datetime import datetime
from decimal import Decimal
from pathlib import Path


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "order_history_kaggle_data.csv"
OUTPUT = ROOT / "order_history_star"
ITEM_SPLIT = re.compile(r",\s+(?=\d+\s*[xX×]\s*)")
ITEM_PATTERN = re.compile(r"^\s*(\d+)\s*[xX×]\s*(.+?)\s*$")
MONEY_COLUMNS = {
    "BILL_SUBTOTAL": "Bill subtotal",
    "PACKAGING_CHARGES": "Packaging charges",
    "restaurant_discount_promo": "Restaurant discount (Promo)",
    "restaurant_discount_other": "Restaurant discount (Flat offs, Freebies & others)",
    "gold_discount": "Gold discount",
    "brand_pack_discount": "Brand pack discount",
    "TOTAL": "Total",
}


def clean_text(value):
    return unicodedata.normalize("NFKC", value).strip()


def clean_item_name(value):
    return re.sub(r"\s+", " ", clean_text(value)).strip(" .")


def item_parts(raw):
    result = []
    for part in ITEM_SPLIT.split(raw):
        match = ITEM_PATTERN.fullmatch(part)
        if not match:
            raise ValueError(f"Cannot parse item: {part!r}")
        name = clean_item_name(match.group(2))
        quantity = int(match.group(1))
        if not name or quantity <= 0:
            raise ValueError(f"Invalid item: {part!r}")
        result.append((name, quantity))
    return result


def cents(value):
    amount = Decimal(value)
    if not amount.is_finite() or amount < 0 or amount.as_tuple().exponent < -2:
        raise ValueError(f"Invalid monetary amount: {value!r}")
    return int(amount * 100)


def money_text(amount_cents):
    return f"{amount_cents // 100}.{amount_cents % 100:02d}"


def promotion_type(construct):
    if construct == "None":
        return "None"
    if construct.lower().startswith("buy 1 get 1"):
        return "Buy 1 Get 1"
    if "%" in construct:
        return "Percentage"
    if construct.lower().startswith("flat rs."):
        return "Flat amount"
    return "Other"


def day_part(hour):
    if hour < 6 or hour >= 22:
        return "Night"
    if hour < 11:
        return "Morning"
    if hour < 15:
        return "Lunch"
    if hour < 18:
        return "Afternoon"
    return "Evening"


def write_csv(name, headers, rows):
    path = OUTPUT / name
    with path.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=headers, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def dimension(values, columns):
    return [dict(zip(columns, value)) for value in sorted(values)]


def outcome_of(row):
    # Ô trống ở nguồn không có nghĩa "không có sự cố", nên dùng nhãn riêng thay cho NULL.
    return (clean_text(row["Order Status"]), clean_text(row["Order Ready Marked"]),
            clean_text(row["Cancellation / Rejection reason"]) or "Not recorded",
            clean_text(row["Customer complaint tag"]) or "Not recorded")


def main():
    # Bước 2-3: Đọc dữ liệu và kiểm tra mã đơn, ngày giờ, món ăn, số tiền.
    with SOURCE.open(encoding="utf-8-sig", newline="") as stream:
        source_rows = list(csv.DictReader(stream))
    print(f"Source: {len(source_rows)} rows, {len(source_rows[0])} columns")
    for column in source_rows[0]:
        empty_count = sum(not row[column].strip() for row in source_rows)
        if empty_count:
            print(f"Missing {column}: {empty_count}")

    seen_order_ids = set()
    prepared = []
    spellings = defaultdict(Counter)
    for row in source_rows:
        order_id = int(row["Order ID"])
        if order_id in seen_order_ids:
            raise ValueError(f"Duplicate Order ID: {order_id}")
        seen_order_ids.add(order_id)
        placed_at = datetime.strptime(row["Order Placed At"], "%I:%M %p, %B %d %Y")
        parsed_items = item_parts(row["Items in order"])
        for name, quantity in parsed_items:
            spellings[name.casefold()][name] += quantity
        amounts = {key: cents(row[column]) for key, column in MONEY_COLUMNS.items()}
        prepared.append((row, order_id, placed_at, parsed_items, amounts))

    # Bước 5: Chuẩn hóa tên món và cộng số lượng món bị lặp trong cùng đơn.
    canonical_name = {}
    for key, counter in spellings.items():
        canonical_name[key] = max(counter, key=lambda name: (counter[name], name))
    expanded = []
    for row, order_id, placed_at, parsed_items, amounts in prepared:
        by_item = defaultdict(int)
        for name, quantity in parsed_items:
            by_item[canonical_name[name.casefold()]] += quantity
        expanded.append((row, order_id, placed_at, list(by_item.items()), amounts))

    # Bước 4: Chọn các thuộc tính cần đưa vào bảng chiều.
    restaurant_values, customer_values, item_values = set(), set(), set()
    outcome_values, promotion_values, distance_values = set(), set(), set()
    date_values, hour_values = set(), set()
    for row, _, placed_at, order_items, _ in expanded:
        restaurant_values.add((int(row["Restaurant ID"]), clean_text(row["Subzone"]),
                               clean_text(row["Restaurant name"]), clean_text(row["City"])))
        customer_values.add((clean_text(row["Customer ID"]),))
        outcome_values.add(outcome_of(row))
        construct = clean_text(row["Discount construct"]) or "None"
        promotion_values.add((construct, promotion_type(construct)))
        distance_values.add((clean_text(row["Distance"]),))
        date_values.add(placed_at.date())
        hour_values.add(placed_at.hour)
        for name, _ in order_items:
            item_values.add((name,))

    restaurants = dimension(
        restaurant_values, ["SOURCE_RESTAURANT_ID", "SUBZONE", "RESTAURANT_NAME", "CITY"]
    )
    customers = dimension(customer_values, ["SOURCE_CUSTOMER_ID"])
    items = dimension(item_values, ["ITEMS_IN_ORDER"])
    outcomes = dimension(
        outcome_values,
        ["ORDER_STATUS", "ORDER_READY_MARKED", "CANCELLATION_REJECTION_REASON", "CUSTOMER_COMPLAINT_TAG"],
    )
    promotions = dimension(
        promotion_values, ["DISCOUNT_CONSTRUCT", "PROMOTION_TYPE"]
    )
    distances = dimension(distance_values, ["DISTANCE"])
    # Chỉ DIM_RESTAURANT (mã nguồn không duy nhất) và DIM_OUTCOME (khóa 4 cột) dùng khóa số.
    restaurants = [{"RESTAURANT_ID": i, **r} for i, r in enumerate(restaurants, start=1)]
    outcomes = [{"OUTCOME_ID": i, **o} for i, o in enumerate(outcomes, start=1)]
    restaurant_id = {(r["SOURCE_RESTAURANT_ID"], r["SUBZONE"]): r["RESTAURANT_ID"] for r in restaurants}
    outcome_id = {(o["ORDER_STATUS"], o["ORDER_READY_MARKED"], o["CANCELLATION_REJECTION_REASON"],
                   o["CUSTOMER_COMPLAINT_TAG"]): o["OUTCOME_ID"] for o in outcomes}

    # Bước 6: Kiểm tra nhãn khoảng cách; không suy đoán khoảng cách chính xác.
    for record in distances:
        label = record["DISTANCE"]
        if label == "<1km":
            record["DISTANCE_INT"] = 0
        else:
            match = re.fullmatch(r"(\d+)km", label)
            if not match:
                raise ValueError(f"Unknown distance label: {label!r}")
            record["DISTANCE_INT"] = int(match.group(1))

    dates = [{
        "FULL_DATE": date.isoformat(),
        "DAY_OF_MONTH": date.day,
        "MONTH_NUMBER": date.month,
        "QUARTER_NUMBER": (date.month - 1) // 3 + 1,
        "YEAR_NUMBER": date.year,
        "WEEKDAY_NUMBER": date.isoweekday(),
        "IS_WEEKEND": int(date.isoweekday() >= 6),
    } for date in sorted(date_values)]
    times = [{"HOUR_NUMBER": hour, "DAY_PART": day_part(hour)}
             for hour in sorted(hour_values)]

    # Bước 6: Đối chiếu tổng tiền, giữ nguyên giá trị nguồn khi có sai lệch.
    fact_rows = []
    bridge_rows = []
    cleaned_items = []
    discrepancy_count = 0
    for row, order_id, placed_at, order_items, amounts in expanded:
        discount_total = sum(amounts[key] for key in (
            "restaurant_discount_promo", "restaurant_discount_other",
            "gold_discount", "brand_pack_discount",
        ))
        discrepancy = (amounts["BILL_SUBTOTAL"] + amounts["PACKAGING_CHARGES"]
                       - discount_total - amounts["TOTAL"])
        if discrepancy:
            discrepancy_count += 1
        outcome = outcome_of(row)
        fact_rows.append({
            "SOURCE_ORDER_ID": order_id,
            "FULL_DATE": placed_at.date().isoformat(),
            "HOUR_NUMBER": placed_at.hour,
            "RESTAURANT_ID": restaurant_id[(int(row["Restaurant ID"]), clean_text(row["Subzone"]))],
            "SOURCE_CUSTOMER_ID": clean_text(row["Customer ID"]),
            "OUTCOME_ID": outcome_id[outcome],
            "DISCOUNT_CONSTRUCT": clean_text(row["Discount construct"]) or "None",
            "DISTANCE": clean_text(row["Distance"]),
            "BILL_SUBTOTAL": money_text(amounts["BILL_SUBTOTAL"]),
            "PACKAGING_CHARGES": money_text(amounts["PACKAGING_CHARGES"]),
            "DISCOUNT_TOTAL": money_text(discount_total),
            "TOTAL": money_text(amounts["TOTAL"]),
            "RATING_VALUE": row["Rating"] or "",
            "KPT_MINUTES": row["KPT duration (minutes)"] or "",
            "RIDER_WAIT_MINUTES": row["Rider wait time (minutes)"] or "",
        })
        for items_in_order, quantity in order_items:
            cleaned_items.append({"SOURCE_ORDER_ID": order_id, "ITEMS_IN_ORDER": items_in_order,
                                  "ITEM_QUANTITY": quantity})
            bridge_rows.append({"SOURCE_ORDER_ID": order_id, "ITEMS_IN_ORDER": items_in_order,
                                "ITEM_QUANTITY": quantity})

    # Bước 7: Xuất CSV để nạp vào kho dữ liệu.
    OUTPUT.mkdir(parents=True, exist_ok=True)
    write_csv("DIM_DATE.csv", list(dates[0]), dates)
    write_csv("DIM_TIME.csv", list(times[0]), times)
    write_csv("DIM_RESTAURANT.csv", list(restaurants[0]), restaurants)
    write_csv("DIM_CUSTOMER.csv", list(customers[0]), customers)
    write_csv("DIM_ITEM.csv", list(items[0]), items)
    write_csv("DIM_OUTCOME.csv", list(outcomes[0]), outcomes)
    write_csv("DIM_PROMOTION.csv", list(promotions[0]), promotions)
    write_csv("DIM_DISTANCE.csv", list(distances[0]), distances)
    write_csv("order_items_cleaned.csv", list(cleaned_items[0]), cleaned_items)
    write_csv("FACT_ORDER.csv", list(fact_rows[0]), fact_rows)
    write_csv("BRIDGE_ORDER_ITEM.csv", list(bridge_rows[0]), bridge_rows)
    print(f"Orders/fact rows: {len(fact_rows)}; bridge rows: {len(bridge_rows)}; items: {len(items)}")
    print(f"Restaurants: {len(restaurants)}; customers: {len(customers)}")
    print(f"Source monetary discrepancies: {discrepancy_count} orders")
    print(f"Output: {OUTPUT}")


if __name__ == "__main__":
    main()
