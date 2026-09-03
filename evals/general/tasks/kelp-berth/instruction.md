# Kelp Berth — window-function support for the sash query builder

`/app/qb` is a small self-authored Python query builder that renders
deterministic, canonical one-line SQL. It already supports
`select / from_ / where / order_by`; it is missing window-function support —
the exact gap you must close. When you are done, the shipped demo runs and
produces `/app/demo_out.sql`.

## Environment layout

- `/app/qb/__init__.py` — package entry; exports `Qb`. **Shipped, do not modify.**
- `/app/qb/core.py` — the builder: `Qb` plus helpers `quote(ident)` and
  `render_order(entry)` implementing the canonical rules below. **Shipped, do
  not modify.** `Qb.select_window(alias, over)` is already wired: it imports
  `window_item` from your extension module and appends the rendered item.
- `/app/demo.py` — the visible demo. It holds `DEMO_SPECS` (structured query
  specs), builds every query strictly through the public API
  (`Qb.select(...).select_window(alias, OverSpec(**kwargs)).from_(...)...`),
  prints canonical SQL to stdout, and writes `/app/demo_out.sql`.
  **Shipped, do not modify.**
- Python 3.12, standard library only.

## Deliverables (you create both)

1. `/app/qb/window.py` — the window-function extension (below).
2. `/app/demo_out.sql` — the byte-exact output of `python3 /app/demo.py`
   once the extension works.

## Canonical SQL rules (the core already follows these; your extension must too)

- Exactly one space between tokens; SQL keywords in UPPER CASE; no trailing
  whitespace anywhere.
- Every identifier — select columns, table names, ORDER BY columns, window
  partition/order columns, aggregate arguments, aliases — is wrapped in
  double quotes, with embedded double quotes doubled (`a"b` → `"a""b"`).
- SELECT list order: all `select()` columns in call order, then all
  `select_window()` items in call order (call interleaving is irrelevant).
- `where()` predicates are raw fragments joined verbatim with ` AND `.
- ORDER BY entries (outer and inside a window) are `col` or `col dir` where
  `dir` ∈ {`asc`, `desc`} (case-insensitive); they render as `"col"` or
  `"col" DESC`.
- Clause order: SELECT, FROM, WHERE, ORDER BY; an empty clause is omitted
  entirely.

Example of a fully built query:

```
SELECT "name", "dept", "salary", ROW_NUMBER() OVER (PARTITION BY "dept" ORDER BY "salary" DESC) AS "rn" FROM "payroll" WHERE active = 1
```

## `/app/qb/window.py` contract

Define exactly these two public names:

### `class OverSpec(function, args=(), partition_by=(), order_by=(), frame=None)`

- `function`: one of `row_number`, `rank`, `dense_rank`, `sum`, `avg`,
  `count`.
- `args`: tuple of column identifiers. Ranking functions take **no** args;
  aggregates take **exactly one**.
- `partition_by`: tuple of column identifiers (may be empty).
- `order_by`: tuple of window ORDER BY entries in the same `col` /
  `col asc|desc` format as the outer builder (may be empty).
- `frame`: `None` or a `(start, end)` pair of bounds from the vocabulary:
  `unbounded preceding`, `N preceding`, `current row`, `N following`,
  `unbounded following` (N a non-negative integer literal).
- Construction must raise `ValueError` on: an unknown function, an
  arg-count mismatch for the function, a `frame` that is not a 2-element
  pair, or a frame-bound string outside the vocabulary.

### `def window_item(alias, over) -> str`

Returns the complete canonical SELECT item string, e.g.:

```
ROW_NUMBER() OVER (PARTITION BY "dept" ORDER BY "salary" DESC) AS "rn"
```

Rendering rules:

- Function name UPPER CASE: `ROW_NUMBER()` (no args), `RANK()`,
  `DENSE_RANK()`, `SUM("sales")`, `AVG("qty")`, `COUNT("item")` — the single
  aggregate argument is quoted.
- OVER contents appear in this fixed order: `PARTITION BY <cols>`,
  `ORDER BY <entries>`, then the frame `ROWS BETWEEN <start> AND <end>` —
  joined with single spaces.
- An empty `partition_by` omits `PARTITION BY` entirely; an empty `order_by`
  omits `ORDER BY` entirely. If all three are empty, render `OVER ()`.
- Frame bounds render UPPER CASE with the integer literal preserved:
  `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`,
  `ROWS BETWEEN 1 PRECEDING AND 3 FOLLOWING`.
- Identifiers and ORDER BY entries use the exact same quoting/rendering as
  `qb.core.quote` and `qb.core.render_order` (you may import them).
- The alias renders as `AS "alias"` (quoted like any identifier).

## Integrating and regenerating the demo output

`Qb.select_window` (in the shipped core) already calls
`window_item(alias, over)` — do not re-implement it. Do not modify
`/app/qb/core.py`, `/app/qb/__init__.py`, or `/app/demo.py`; the verifier
byte-compares all three against the shipped copies.

Once `/app/qb/window.py` is complete, run:

```
python3 /app/demo.py
```

This prints the canonical SQL of the five `DEMO_SPECS` queries and writes
`/app/demo_out.sql` (the same text). That file is your second deliverable.

## How the grader probes it

- Byte-compares `/app/qb/core.py`, `/app/qb/__init__.py`, `/app/demo.py`
  against pristine copies (tamper detection).
- Imports `/app/qb/window.py`, checks that `OverSpec` and `window_item`
  exist, and spot-checks `window_item` output strings directly.
- Re-renders the demo's `DEMO_SPECS` with an **independent reference
  implementation** and requires both `python3 /app/demo.py` stdout and
  `/app/demo_out.sql` to match byte-for-byte.
- Runs hidden usage matrices through the real builder API —
  `Qb().select(...).select_window(alias, OverSpec(...)).from_(...)
  .where(...).order_by(...)`. They cover: all six functions, several
  windows per query, window + where + outer ORDER BY interplay, call
  interleaving, empty `partition_by`, empty window `order_by`, bare
  `OVER ()`, edge frames (`ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING`,
  `UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING`, `CURRENT ROW AND 2
  FOLLOWING`, ...), plus an identifier containing an embedded double
  quote — each compared byte-for-byte against the reference.
- Checks that invalid `OverSpec` constructions (unknown function, wrong arg
  counts, malformed frame) raise `ValueError`.

The hidden matrices use tables, columns, aliases, functions, and frame
combinations that do not appear in the visible demo — hardcoding the demo
output cannot pass them, and every hidden case runs through the same public
API the demo uses.

## Constraints

- Python 3.12 standard library only; nothing to install, no network access.
- Everything is deterministic by construction (fixed specs, no randomness,
  no wall-clock).