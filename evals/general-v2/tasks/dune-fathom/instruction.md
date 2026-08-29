# Fathom Edge Services — bring the backend live

You are handed a **services repo** for a small block-explorer backend. The repo already
contains a partially-written API server (`/app/server.py`), a source-of-truth accounts CSV,
and two helper tools. Your job is to **repair and complete** the service so the grader can
boot it, query it over the network on parameters you have not seen, and byte-compare the
files you leave behind. Everything must follow the exact contracts below.

Work only inside the running container. `/tests` and `/solution` are **not** available to
you (do not attempt to read them). You may install nothing extra; `flask`, `sqlalchemy` and
`requests` are already installed.

---

## Fixed inputs (your repo — do not modify the bytes)

- `/app/data/accounts.csv` — the authoritative **source** of the accounts table, header
  `id,address,balance` plus 6 rows. This is the single source of truth.
- `/app/tools/fixture_server.py` — a ready-made local HTTP server that serves two raw byte
  payloads at `GET /alpha` and `GET /beta`. Run it with `python3 /app/tools/fixture_server.py`.
- `/app/tools/export_csv.py` — a ready-made exporter that reads the SQLite table
  `accounts` and writes `/app/dump.csv`. Use it as-is; do not change its output format.
- `/app/server.py` — the starter API server. **It is broken**: it binds only
  `127.0.0.1`, `/render` executes its input as a Jinja template instead of echoing it
  literally, the status/accounts/fibonacci routes skip required validation and error
  codes, and there is no JSON error handler. Rewrite/repair it per the contract below.

Ports are fixed: **API on `8787`**, fixture server on **9898**. Do not pick others.

---

## Deliverables (all under `/app`, all required)

| Path | What it must be |
|------|-----------------|
| `/app/server.py` | A Flask API program implementing every route below, **binding all interfaces (`0.0.0.0`) on port `8787`**, that boots cleanly from a pristine container. |
| `/app/server.out` | A log file containing the readiness line `FATHOM-API-UP 0.0.0.0:8787` from at least one clean boot of that server. |
| `/app/data/dump_chain.db` | SQLite DB whose table `accounts(id INTEGER PRIMARY KEY, address TEXT, balance INTEGER)` holds exactly the normalized rows of `accounts.csv`. |
| `/app/dump.csv` | CSV exported **from that DB table** (same rows as the DB and the source). |
| `/app/delivered/alpha.bin` | **Byte-for-byte** content of the fixture server's `GET /alpha`. |
| `/app/delivered/beta.txt` | **Byte-for-byte** content of the fixture server's `GET /beta`. |

---

## 1. The database and CSV (three-way consistency)

1. Build `/app/data/dump_chain.db` and seed the `accounts` table **exactly** from
   `/app/data/accounts.csv`: normalized values (`id` int, `address` trimmed, `balance` int),
   all 6 rows, ordered by ascending `id`. Seed it when the server first boots (or before).
2. Then run `python3 /app/tools/export_csv.py` to write `/app/dump.csv` from the DB table.

The grader will independently query the live DB table and parse `/app/dump.csv`, and require
that **all three** (source CSV, DB table, exported `dump.csv`) list the same normalized rows.

---

## 2. The API server — `/app/server.py`

A Flask app that **binds all interfaces** on **port `8787`**, stays up in the background,
and prints the readiness line `FATHOM-API-UP 0.0.0.0:8787` to stdout on every boot (include
it in `/app/server.out`). Implement exactly these routes; **all** responses are JSON except
`/render`:

### `GET /health` → `200 {"status":"ok"}`

### `GET /api/fibonacci?k=<int>`
- `k` is required and must parse as an integer. Otherwise `400 {"error": "invalid k"}`.
- `k < 0` → `400 {"error": "k must be non-negative"}`.
- `k > 200` → `400 {"error": "k out of range"}`.
- Else `200 {"k": <int>, "value": <F(k)>}` with `F(0)=0`, `F(1)=1`,
  `F(n)=F(n-1)+F(n-2)`, computed exactly with native integers (no floats, no overflow
  wraps — `k` up to 200).

### `GET /api/status/block/<block_id>` and `GET /api/status/tx/<tx_id>`
`<block_id>` / `<tx_id>` arrive as URL path segments.

Declared status sets:
- Confirmed block ids: `1000, 2000, 3000, 4000`. Pending block ids: `1500, 2500`.
- Confirmed tx ids: `7001, 7002, 8001`. Pending tx ids: `9000, 9100`.

Behavior:
- The segment is **not** an integer → `400 {"error": "invalid id"}`.
- The id is in a declared set → `200 {"type": "block", "id": <int>, "status": "confirmed"|"pending"}`
  (use `"type": "tx"` for the tx route).
- The id is an integer but in no set → `404` with a JSON body
  (`{"error": "block not found"}` for block, `{"error": "transaction not found"}` for tx).

### `GET /api/accounts?offset=?&limit=?` (paged listing)
- Read `offset` (default `0`) and `limit` (default: **return all**). Rows are ordered by `id`.
- Both, when present, must be non-negative integers; anything else →
  `400 {"error": "offset and limit must be non-negative integers"}`.
- Response: `{"total": <N>, "result": [ {"id":..,"address":..,"balance":..}, ... ]}` where
  `result` is the slice `rows[offset : offset+limit]` of the id-ordered rows. A `limit` of
  `0` returns `[]`; an offset past the last row returns `[]`.

### `GET /render?text=<payload>` (**plain-text echo — neutralize the template hole**)
This route must return `200` with `Content-Type: text/plain` and a body that is **exactly**
the literal `text` value given — **never run through a template engine, never evaluated,
never HTML-escaped, never modified**. In particular, each of these must be returned verbatim
(byte-identical to what was sent):

```text
{{7*7}}        ->  "{{7*7}}"          (NOT the evaluated 49)
{{ config }}   ->  "{{ config }}"
{% set x = 1 %}->  "{% set x = 1 %}"
<b>bold</b>    ->  "<b>bold</b>"       (NOT &lt;b&gt;bold&lt;/b&gt;)
{{''.__class__}} -> "{{''.__class__}}"
plain fathom   ->  "plain fathom"
```

If `text` is absent, the body is the empty string (still `200`, `text/plain`). The current
starter route is the template hole — fix it so input is emitted as literal data and cannot
execute.

### Unknown routes and errors
Any **other** path (e.g. `/api/does/not/exist`) must return `404` with a **JSON** error body
(`{"error": "not found"}`), not an HTML error page. Invalid requests that your routes don't
map themselves should also surface as JSON (`400`/`500` handlers are good practice).

---

## 3. Retrieve the remote files byte-for-byte

Start the fixture server yourself (`python3 /app/tools/fixture_server.py &`), which listens
on `http://127.0.0.1:9898`, and fetch over HTTP (`requests` recommended):

- `GET http://127.0.0.1:9898/alpha` → save to `/app/delivered/alpha.bin`
- `GET http://127.0.0.1:9898/beta`  → save to `/app/delivered/beta.txt`

Persist the **raw response body bytes** (`resp.content`), **not** a `.text` re-encoding:
`/alpha` is not valid UTF-8, so any text-transcoding step corrupts it. The grader starts a
fresh copy of the fixture server and requires **byte equality** with your two files.
Create `/app/delivered/` if needed.

---

## Edge cases the grader will exercise (all must behave per the contract)

1. `/api/fibonacci`: missing `k`, non-integer `k`, `k<0`, `k>200` → `400` JSON; `k=0`,
   `k=1`, and a large `k` like `90`/`200` → exact `value`.
2. `/api/status/block/<id>` & `/api/status/tx/<id>`: non-integer id → `400` JSON; integer
   id in no set → `404` JSON (block vs tx message); confirmed vs pending → correct status.
3. `/api/accounts`: `offset`/`limit` non-negative integers only; `limit:0` → `[]`;
   overshooting offset → `[]`; correct slice and `total` otherwise.
4. `/render`: SSTI-style and HTML payloads echoed **verbatim** (bytes unchanged), `200`,
   `text/plain`; empty/missing `text` → empty body.
5. Unknown paths → `404` with a JSON `error` body.
6. The grader queries **both `127.0.0.1:8787` and the container's external IP** — both must
   answer `200` (this only works if you bind `0.0.0.0`), and the service must stay up for
   the whole grading run.

## What is graded

A single container. The grader boots `server.py`, queries all routes (edge cases above and
hidden parameters) on both addresses, validates schemas/values, then cleanly stops it. It
also checks: source CSV vs DB table vs `/app/dump.csv` all match; `/app/delivered/alpha.bin`
& `beta.txt` byte-equality; `/app/server.out` records the readiness line. Any mismatch → 0.
