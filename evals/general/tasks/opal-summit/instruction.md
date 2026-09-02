# Opal Summit — revenue ranking bench

The Opal Summit merchandising bench ships three small fixtures: a product
catalog, an order ledger, and a reporting period. Build a small, reusable
Python 3 program that joins the ledger against the catalog, keeps only the
orders inside the reporting period, aggregates revenue per product, and ranks
the products. The verifier will run your program again on fresh inputs
matching the same schemas, so it MUST be written to take its input paths and
output path as command-line arguments and work correctly for ANY input files
with the documented schema — never hard-code the shipped fixtures.

## Deliverables

Write exactly two artifacts under `/app`:

1. **`/app/solve.py`** — a runnable Python 3 program. Command-line contract:

   ```
   python3 /app/solve.py [ORDERS.csv PRODUCTS.csv PERIOD.txt OUTPUT.json]
   ```

   Defaults: `/app/orders.csv`, `/app/products.csv`, `/app/period.txt`,
   `/app/report.json`.

2. **`/app/report.json`** — the ranking your program produces for the shipped
   fixtures (run your `solve.py` yourself to generate it).

Do NOT modify any shipped input fixture.

## Input contracts

- **`ORDERS.csv`** — CSV header `order_id,product_id,quantity,unit_price,date`.
  Fields may carry surrounding whitespace, which must be trimmed. Blank lines
  may appear anywhere and are skipped. An order row is **valid** iff its
  `quantity` parses as an integer (possibly negative, e.g. a refund) and its
  `unit_price` parses as a decimal number (e.g. `19.99`, `-3`, `2.5`) and its
  `date` is a real `YYYY-MM-DD` calendar date. Any other row (bad/missing
  fields, non-numeric quantity or price, impossible dates like `2025-02-30`)
  is invalid and skipped.
- **`PRODUCTS.csv`** — CSV header `product_id,product_name,category`; same
  trimming rules. `product_name` and `category` may be any text (possibly
  empty after trimming).
- **`PERIOD.txt`** — lines `from=YYYY-MM-DD` and `to=YYYY-MM-DD` (either
  order; both present). The period is **inclusive on both ends**.

## Report computation (exact)

1. Keep only valid order rows whose `date` satisfies `from <= date <= to`.
2. An order whose (trimmed) `product_id` does not appear in the catalog is
   ignored entirely.
3. For each catalog product, over the kept orders:
   - `units` = sum of `quantity` (0 if none),
   - `orders` = number of kept orders (0 if none),
   - `revenue` = sum of `quantity * unit_price` over the kept orders,
     rounded to 2 decimal places (0.0 if none).
4. **`products`**: every catalog product, sorted by `revenue` descending, then
   `product_id` ascending (lexicographic) for ties. Each entry is an object
   with keys in this order: `product_id`, `product_name`, `category`,
   `units`, `orders`, `revenue`.
5. **`top_products`**: the `product_id` values of the first three entries of
   `products` (fewer if the catalog is smaller).
6. **`total_revenue`**: the sum of all kept orders' `quantity * unit_price`,
   rounded to 2 decimal places.

## Output format (exact)

`/app/report.json` must be JSON with exactly these keys, in this order:

```json
{
  "period": {"from": "<YYYY-MM-DD>", "to": "<YYYY-MM-DD>"},
  "products": [ ... ],
  "top_products": ["<id>", "<id>", "<id>"],
  "total_revenue": <number>
}
```

## Edge cases the hidden checks probe

- An **orders file with no valid rows** (header only, or all rows invalid):
  every catalog product ranks with `units: 0, orders: 0, revenue: 0.0`, sorted
  by `product_id` ascending; `top_products` is the first three ids;
  `total_revenue: 0.0`.
- Orders **outside the period** on either side (period boundaries are
  inclusive: an order dated exactly `from` or `to` counts).
- Orders referencing **unknown product ids** (ignored).
- **Tied revenue** between products (must break by `product_id` ascending).
- Malformed rows: non-integer quantity, non-numeric price, impossible or
  wrongly formatted dates, missing fields, whitespace-padded fields.
- Negative quantities (refunds) subtracting from revenue.
- Whitespace-padded headers and cells in both CSVs.

## Rules

- Output must be deterministic and require **no network access**.
- The verifier re-runs the program on fresh hidden inputs and requires the
  outputs to match independently recomputed expected values; wrong period
  filtering, a missed join, or a mis-summed revenue fails the case.
