# Reconcile sales and returns ledgers into a revenue report

You operate on a small order-fulfillment dataset: a line-items ledger, a
returns ledger, and a reporting period. Build a reusable command-line program
that joins the two ledgers, filters to the period, and produces an aggregated
per-product revenue report. The program must work **on any input** conforming
to the contract below, not just the provided files — the grader runs it again
on hidden inputs.

## Environment

- Working directory: `/app`. It already contains
  `/app/lineitems.csv`, `/app/returns.csv`, and `/app/period.txt`.
  Python 3.12 is available as `python3`.
- **Do not modify any of these three input files.**

## Deliverables (both required)

1. `/app/solve.py` — a runnable Python program with this interface:

   ```
   python3 /app/solve.py <lineitems.csv> <returns.csv> <period.txt> <output_json>
   ```

   Standard library only; no network access.

2. `/app/answer.json` — the report your program produces **when run on the
   provided `/app` inputs**:
   ```
   python3 /app/solve.py /app/lineitems.csv /app/returns.csv /app/period.txt /app/answer.json
   ```

## Input contracts

**`lineitems.csv`** — the first non-blank line is a header (not validated, not
counted); every subsequent line is a data row with exactly these 5
comma-separated columns:

```
order_id,date,product_id,units,unit_price
A-100,2032-01-03,P-1,2,19.99
```

- Surrounding whitespace on every field must be trimmed before validation.
- Blank lines (empty or whitespace-only) are skipped silently.
- A data row is **valid** iff it has exactly 5 fields, `order_id` and
  `product_id` are non-empty, `date` matches `YYYY-MM-DD` and is a real
  calendar date, `units` is a positive integer, and `unit_price` is a
  non-negative decimal number with at most 2 fraction digits (e.g. `19.99`,
  `120.00`, `7`). Anything else is a malformed row: counted in
  `malformed_line_items` and skipped.
- The same `(order_id, product_id)` pair may appear on multiple data rows.

**`returns.csv`** — same conventions; the first non-blank line is a header;
data rows have exactly 4 columns:

```
return_id,order_id,product_id,units_returned
```

- A return row is **valid** iff it has exactly 4 fields, `return_id`,
  `order_id`, and `product_id` are non-empty and whitespace-free, and
  `units_returned` is a positive integer. Otherwise it is malformed: counted
  in `malformed_returns` and skipped.

**`period.txt`** — plain text with one `from=YYYY-MM-DD` line and one
`to=YYYY-MM-DD` line, in either order; blank lines ignored. The period
`[from, to]` is **inclusive on dates**.

## Computation (exact)

1. **In-range line items**: only line items whose date satisfies
   `from <= date <= to` participate in revenue. A return whose matching line
   item is out of range (or nonexistent) does **not** apply.
2. **Gross revenue**: for each in-range line item, add `units * unit_price`
   to that product's `gross` and `units` to that product's `units_gross`.
3. **Returns**: for each valid return row, find the **first in-range line
   item, in file order**, with the same `(order_id, product_id)`; subtract
   `units_returned * unit_price` (of that matched line item) from the
   product's revenue (accumulated as `returned`) and subtract
   `units_returned` from the product's `units_net`. If no in-range line item
   matches, increment `unmatched_returns` and apply nothing. Multiple returns
   may hit the same line item; each applies independently.
4. `net` of a product = `gross - returned`; `units_net = units_gross -`
   total `units_returned` applied to that product.
5. `orders_in_range` = number of distinct `order_id` values among in-range
   line items.
6. All money values (`total_gross`, `total_returned`, `total_net`, and the
   per-product `gross`/`returned`/`net`) are rounded to **2 decimal places**
   (plain `round(x, 2)`). `total_net = total_gross - total_returned` computed
   on the unrounded sums, then rounded.

## Required output JSON

Exactly these top-level keys (contents compared by value):

```json
{
  "period": {"from": "YYYY-MM-DD", "to": "YYYY-MM-DD"},
  "total_gross": 0.0,
  "total_returned": 0.0,
  "total_net": 0.0,
  "orders_in_range": 0,
  "malformed_line_items": 0,
  "malformed_returns": 0,
  "unmatched_returns": 0,
  "products": {
    "<product_id>": {
      "units_gross": 0,
      "gross": 0.0,
      "returned": 0.0,
      "net": 0.0,
      "units_net": 0
    }
  },
  "top_products": ["<product_id>", "..."]
}
```

- `period` echoes the parsed period.
- `products` contains one entry per product with at least one in-range line
  item **or** at least one applied return. `units_net` may be negative.
- `top_products`: the product ids ranked by `net` descending (ties broken by
  product id ascending; ties are judged on the rounded `net` values), capped
  at the top **3**. If fewer than 3 products exist, the list is shorter; if
  no products exist, it is `[]`. Zero or negative net products still rank.

## Edge cases the grader probes

- Returns whose matching line item falls outside the period or does not exist
  (unmatched, no effect).
- A period that contains no line items at all: totals `0.0`,
  `orders_in_range` 0, `products` `{}`, `top_products` `[]`.
- Exactly tied net revenues changing the rank order (product id breaks ties).
- Repeated `(order_id, product_id)` pairs: a return matches the FIRST
  in-range occurrence in file order, at that row's unit price.
- Malformed line-item and return rows (bad units, over-precise prices, wrong
  column counts, non-positive `units_returned`) are counted and skipped.
- Whitespace-padded fields and blank lines anywhere.

## Constraints

- The verifier runs `/app/solve.py` unchanged on hidden inputs that follow the
  same format, so never hard-code to the provided files' contents or names.
- Deterministic; standard library only; no network access.
- Do not modify `/app/lineitems.csv`, `/app/returns.csv`, or `/app/period.txt`.
