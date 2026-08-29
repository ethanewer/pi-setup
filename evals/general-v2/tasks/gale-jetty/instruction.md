# gale-jetty: ship the ledger close-out reconcile pipeline

You are the platform engineer for **Gale Jetty Logistics**. A batch of shipping
documents has arrived in `/app/inbox`, their per-row extraction specs live in
`/app/masks.csv`, and the fiscal ledger for the same invoices arrives in
**three heterogeneous formats** in `/app/hx/`. Your job is to write a
reproducible reconcile program that closes out the batch: it must classify and
relocate the documents, iterate every extraction row, parse the heterogeneous
ledger into one schema, recover a matrix, cross-check the fiscal figures to
flag the single inconsistent value, and rank a shortlist of candidate
descriptors by proximity to a target — then leave every result behind as a
real, on-disk artifact.

Work inside `/app`. **Do not modify** `/app/compute_seq.py` or the shipped
fixtures. Write your own program files into `/app` and make
`python3 /app/reconcile.py` regenerate every deliverable from scratch.

---

## Inputs (already in `/app`, do not edit)

```
/app/inbox/            mixed shipping documents to classify and relocate
/app/masks.csv         one row per invoice: extraction cell rectangle + expected fee
/app/hx/               heterogeneous fiscal ledger, one schema (invoice_id, amount, fee)
                       spread across ledger.csv, ledger.json, ledger.parquet
/app/candidates.json   candidate descriptors to filter/rank: [{"id","metric"}, ...]
/app/config.json       {"grid":{"rows","cols"}, "close":{"target","tolerance"}}
/app/compute_seq.py    the sequential iteration constant: ITERATIONS = <int>
```

- **Documents** in `/app/inbox`: a file is an **invoice** iff its first
  non-empty line is exactly `INVOICE`; every other file is **other**. These are
  the only two classes.
- **`masks.csv`** columns: `invoice_id,row0,col0,row1,col1,expected_fee`. Each
  row-carves a cell rectangle `(row0,col0)-(row1,col1)` on the `rows x cols`
  logical grid from `config.json`. Rectangles may be given with **reversed
  corners** (`row0 > row1` or `col0 > col1`); normalize by taking
  min/max so the rectangle is always well ordered.
- **Heterogeneous ledger** (`/app/hx/`): the same records represented as
  `ledger.csv` (comma header), `ledger.json` (JSON array of objects), and
  `ledger.parquet`. Any subset of these formats may actually be present — your
  parser must tolerate a missing format and still merge whatever is there into
  one schema keyed by `invoice_id` (last occurrence wins on repeat).

---

## Your deliverables

1. **`/app/reconcile.py`** — executable (shebang `#!/usr/bin/env python3`,
   `chmod +x`), with CLI:
   ```
   python3 /app/reconcile.py [--input DIR] [--output DIR]   # default both /app
   ```
   It performs the whole pipeline and writes every artifact under `--output`
   (re-running it must be idempotent and reproduce the same state). The
   pipeline:

   a. **Classify & relocate** every file under `<input>/inbox` into
      `<output>/ledger/invoice/` or `<output>/ledger/other/`, leaving the inbox
      empty. No file may be lost, duplicated, or misplaced.
   b. **Iterate EVERY `masks.csv` row** (never a subset): for each row append
      one line to `<output>/prompts.txt` in the form
      `prompt[<i>] invoice=<id> rect=(<r0>,<c0>,<r1>,<c1>)` (normalized corners,
      `i` is 1-based), and build one per-row SAM-style bool mask (an
      `rows x cols` grid, `True` inside the normalized rectangle, inclusive).
      Persist the stacked masks as `<output>/inference.npz` under key `masks`
      with shape `(N, rows, cols)`.
   c. **Recover the matrix**: use the extraction engine (below) to parse the
      heterogeneous ledger and write `<output>/mart.npy` — a dense `(N, 3)`
      float array, invoice order = the `masks.csv` row order, with
      `[amount, fee, (amount+fee)*ITERATIONS]` per row, `ITERATIONS` obtained
      **by import** (see (e)).
   d. **Close-out sheet** `<output>/sheet.jsonl` (JSON Lines, one object per
      line) writing cell values at exact addresses on sheet `"GJ"`: for invoice
      row `k` (1-based index in masks order) emit
      `{"sheet":"GJ","address":"A<k>","value":<amount>,"invoice":"<id>"}` and
      likewise `B<k>`/`C<k>` for fee / cost, then a
      `{"sheet":"GJ","address":"TOTAL","value":<sum of costs>,"invoice":"*"}`
      record, then a `NOTE` record carrying `","`.join`ed inconsistent ids or
      `OK` when none.
   e. **Sequential constant reuse**: `ITERATIONS` must come from the companion
      sequential module through an import chain — create
      `/app/compute_parallel.py` that imports it from `/app/compute_seq.py`,
      and have `/app/extract.py` and `/app/reconcile.py` import `ITERATIONS`
      from `compute_parallel`. Do **not** restate the number anywhere inline.
   f. **Runnable extraction engine**: create `/app/extract.py` — an executable
      script (also importable) with the same `--input/--output` CLI that parses
      the heterogeneous ledger and writes `<output>/mart.npy`; `reconcile.py`
      must delegate the matrix write to it (import its build function), so the
      `.npy` is genuinely produced by that runnable script.
   g. **Fiscal cross-check**: for every mask row compare the ledger fee (from
      the parsed heterogeneous data) against `expected_fee` (1e-9 tolerance);
      write the single inconsistent invoice id (or all of them, comma-joined,
      or the literal `NONE`) to `<output>/mismatch.txt` (one line).
   h. **Filter/rank candidates**: from `<input>/candidates.json`, keep only
      candidates whose `|metric - target| <= tolerance` (inclusive boundary),
      and emit `<output>/ranked.json` — a JSON array of
      `{"id","metric","target","distance","score"}` where
      `distance = round(|metric-target|,4)` and `score = round(1/(1+distance),6)`,
      sorted by descending `score`, ties by ascending `id`.

2. **`/app/mart.npy`** — the recovered matrix produced and left behind by the
   pipeline (see 1c/1f).
3. **`/app/sheet.jsonl`** — the close-out sheet produced and left behind (see
   1d).

---

## How you will be graded (read-only, after you finish)

The verifier re-invokes `/app/reconcile.py` (idempotently) on the visible
fixtures and on the hidden scenarios, then **independently re-derives** every
expected artifact from the raw inputs and compares: exact matrix shape/values
(`(N,3)` orientation), every sheet address+value, the ranked candidate list
(including the inclusive tolerance boundary and id tie-break), the mismatch
ids, the full per-row `prompts.txt` line-for-line, the per-row mask grid count
and shape, inbox-emptied + exact ledger classification sets, and the import
evidence (`compute_parallel` ↔ `compute_seq`, `extract` ↔ `compute_parallel`).
Hidden scenarios vary the invoice set/amounts, drop ledger formats
(parquet-only, csv+json-only, empty ledger), reverse rectangle corners, place
candidates exactly on the tolerance boundary, and shrink to a zero-row input —
your program must generalize to all of them and must never crash on a malformed
or missing input file. Nothing else is checked.
