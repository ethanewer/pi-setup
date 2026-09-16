# conduit-tarn: restore multi-leg order handling in `conduit`

## Environment

`/app/conduit` is a git repository containing "conduit", the Tarn trading
desk's internal tool that normalises vendor order feeds (CSV) into canonical
order summaries (JSON). You are handed a complete, working repository:

- A linear `main` branch with **40 commits** and release tags `v0.1.0`,
  `v0.2.0`, `v0.3.0`, `v0.9.0`, `v1.0.0`.
- The working tree is clean and the full test suite passes:
  `cd /app/conduit && python3 -m pytest -q tests/`
- The tool runs with `python3 -m conduit <feed.csv> <out.json>`.
- Installed in the image: Python 3.12, `pytest`, `git`.

## The tool contract (this is the source of truth)

### Input feed

CSV with a header row, one fill per line:

    order_id,side,instrument,quantity,price,timestamp

- `order_id` — non-empty string. **Basket orders span several rows that
  share one order id.** Every fill of a basket order must survive into the
  canonical document.
- `side` — `BUY` or `SELL`.
- `instrument` — non-empty string.
- `quantity` — positive integer.
- `price` — positive number.
- `timestamp` — ISO-8601, `YYYY-MM-DDTHH:MM:SS` (fractional seconds allowed).

Rows that fail to parse or validate are skipped and reported in the
`warnings` list (with the physical line number) instead of aborting the run.

### Canonical output

    {"orders": [ ... ], "warnings": [ ... ]}

One entry per distinct order id, in the order the order id first appears in
the feed:

    {"order_id": "...", "fills": [...], "fill_count": N,
     "gross": G, "fee": F, "net": N, "sides": [...]}

- `fills` — one object per fill row, fields `seq`, `side`, `instrument`,
  `quantity`, `price`, `timestamp`. `seq` is the 1-based position of the fill
  among the accepted rows. Within an order the fills are ordered by
  `timestamp`, breaking ties by `seq`.
- `fill_count` — the number of fills. Every fill row of a basket order must
  appear here.
- `gross` — sum of `quantity * price` per fill, rounded to two decimals.
- `fee` — `round(gross * 0.0015, 2)`.
- `net` — `round(gross - fee, 2)`.
- `sides` — the distinct sides in the order, in order of first appearance.

The exact schema, grouping rules and rounding are also documented in
`/app/conduit/docs/format.md`.

## Incident report (ticket TARN-4821)

> **Basket orders are summarised as a single fill.** Any order that spans more
> than one row in the vendor feed is reported in the canonical document with
> one fill, the wrong gross/fee/net, and a truncated `sides` list. Orders with
> a single fill are unaffected. This is a recent regression: release v0.3.0
> summarised basket orders correctly. Suspected cause is one of the commits
> since then — the fix must not change the output contract.

You can reproduce the defect yourself: `/app/conduit/samples/feed_multi_line.csv`
is a basket feed.

## Your task

1. **Reproduce** the defect with the CLI.
2. **Locate the commit that introduced it.** `git bisect` between the release
   tags and `HEAD` is the intended tool; the regression is a single commit.
3. **Determine the root cause** and fix it. Do not change the input format,
   the canonical output contract, the field ordering, or the CLI behaviour.
4. **Add a new regression test file** under `tests/` that fails when the test
   suite runs against the code as shipped (pre-fix) and passes once your fix
   is in place.
5. **Commit** the fix and the regression test, and leave `/app/conduit` on
   `main` with a clean working tree.

## Constraints

- Work only inside `/app/conduit`. Never read or modify anything under
  `/tests/` or `/solution/`.
- **Do not rewrite the shipped history**: no rebase, amend, `reset` or
  filter of any commit that exists today. Every commit currently reachable
  must remain reachable when you are done. Your own fix may be committed on
  top (one commit or several).
- Do not delete or rename any existing test file.
- Existing tests must keep passing; hidden verification feeds only use the
  documented input format.

## Deliverable

`/app/conduit` — the repository, in a state where the defect is fixed, a new
regression test exists and passes, the whole suite passes, and the shipped
history is intact. The verifier re-runs the tool against fresh hidden feeds in
the affected class, runs the full suite (including against the shipped
pre-fix code, where the new regression test must fail), and checks that the
original commits are still reachable.