# Fernbrook Nursery catalog client

You are working on a plant-nursery catalog integration rooted at `/app`. The
image ships a **local HTTP origin** (`/app/origin.py`) that serves the
nursery's public offers page as HTML. You must write an HTTP client that
fetches that page and parses it into structured records.

The grading harness later **executes** your client unchanged against *fresh*
origin servers (different nursery data, different HTML edge cases), so write
it generically against the documented page contract below — never hard-code
the reference data shown in `/app/ref_config.json`.

Work only under `/app`. Do **not** modify `/app/origin.py` or
`/app/ref_config.json`.

## Deliverables (both required)

1. `/app/solve.py` — an **executable** Python 3 client. Standard library only
   (`urllib.request`, `json`, `html.parser`, …). No pip packages. Interface:

   ```
   python3 /app/solve.py --origin http://127.0.0.1:<port> --out <path>
   ```

   It must issue `GET /` on the origin, parse the returned HTML document, and
   write the JSON report to `<path>`.

2. `/app/answer.json` — the report produced by **running** your client against
   the live reference origin. Start it, then run your client:

   ```
   python3 /app/origin.py /app/ref_config.json 20090 &
   python3 /app/solve.py --origin http://127.0.0.1:20090 --out /app/answer.json
   ```

## Offers page contract

`GET /` returns one HTML page (UTF-8). It contains:

- a `<title>` element — report its trimmed text as `title`;
- a `<section id="offers">` holding the plant offers. Data records are
  `<article class="plant">` blocks inside that section, in document order.
  Each article contains, in any order:
  - `<h2 class="cultivar">…</h2>` — the cultivar name (trim whitespace);
  - `<span class="sku">…</span>` — the SKU (trim whitespace);
  - `<span class="price">$<number></span>` — a dollar price, e.g. `$12.50`
    or `$9`. Report the numeric value **without** the `$` as a JSON number
    (integral prices may be reported as e.g. `9.0`).
  - `<span class="stock">In stock: <N></span>` — report the integer `N` —
    or the text `Sold out`, which must be reported as `0`.
- A decoy section `<section id="care-guides">` also contains
  `<article class="plant">` blocks with the **same** inner classes. Articles
  in that section (or anywhere outside `#offers`) must be ignored.
- Some articles omit fields: a missing `<span class="price">` → `price`
  is `null`; a missing `<span class="stock">` → `stock` is `null`.
- Whitespace between tags may be messy (newlines, indentation, blank lines);
  trim every text node.
- Values may contain HTML entities (e.g. `&amp;`, `&#39;`) — unescape them.

## Report JSON

The output file must be valid JSON of exactly this shape:

```json
{
  "title": "<page title>",
  "plants": [
    {"sku": "FB-2201", "cultivar": "Auricula 'Mist'", "price": 12.5, "stock": 34}
  ]
}
```

`plants` lists the `#offers` articles in document order with keys `sku`,
`cultivar`, `price`, `stock` exactly as specified above.

## Constraints

- No network access beyond the local origin; standard library only.
- Do not modify `/app/origin.py` or `/app/ref_config.json`.
- The verifier reruns your client on hidden origin scenarios; it must never
  depend on the reference data, fixed ports, or fixed values.
