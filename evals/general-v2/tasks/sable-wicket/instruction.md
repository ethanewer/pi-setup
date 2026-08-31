# Apply the ledger's audited line repairs through patchdeck

The candle-works nightly audit flagged **five single-line defects** in
`/app/lib/wickkit.py` (a small sizing-helper library). The audit report
`/app/audit/findings.json` locates every defect: each finding has an `id`
(`F-01` … `F-05`), the `file`, the exact 1-based `line` number, and the
`excerpt` — the exact current text of the defective line.

All repairs **must be applied through the supplied `patchdeck` tool** by
writing fix-request files and running the applier. Direct edits to
`/app/lib/wickkit.py` are not accepted: a request whose `old` text no longer
matches the file's current line is REJECTED, and every rejected attempt burns
budget.

## The fix budget

The audit allows **exactly one attempt per finding: `max_attempts = 5`**.
`patchdeck` consumes one attempt per request file it processes (applied or
rejected) and records every attempt as one JSON line in
`/app/tools/patchdeck.log`. The run's success check fails when:

- the log contains **more than 5 attempts**, or
- **any** attempt was `REJECTED`, or
- any finding was never `APPLIED` exactly once.

So you get no slack: each of the five requests must be correct on the first
try. Read the audit, write the requests carefully, apply once, and verify.

## The protocol

1. Read `/app/audit/findings.json` (ids, lines, excerpts) and the module
   docstrings in `/app/lib/wickkit.py` — each docstring states the normative
   behavior the defective line violates.
2. For each finding write one request file `/app/requests/F-xx.json`:
   ```json
   {"finding": "F-01", "file": "/app/lib/wickkit.py", "line": <audited line>,
    "old": "<exact audited excerpt>", "new": "<corrected single line>"}
   ```
   `"old"` must byte-match the audited `excerpt`; `"new"` is the full
   replacement line (keep the original indentation).
3. Apply them in one shot:
   ```
   python3 /app/tools/patchdeck.py apply
   ```
4. Check `/app/tools/patchdeck.log`: you need exactly five `APPLIED` entries.
   If anything came back `REJECTED` the budget is already blown — re-read the
   contract instead of resubmitting.
5. Sanity-check the repaired library: `python3 /app/selfcheck.py` must report
   7/7 passed.

## The normative contracts (from the module docstrings)

- `unit_cost(cents, units)` — floor of `cents / units` (`units >= 1`).
- `bulk_total(cents, units)` — `cents * units`, minus a floored 5% discount
  (`total - total * 5 // 100`) **only when `units >= 12`**.
- `wick_length(inches)` — `round(1.5 + 0.25 * inches, 2)`.
- `melt_pool(diameter)` — clamped into the closed interval `[1.0, 4.0]`.
- `batch_rows(n)` — the row indices `0 .. n-1` as a list.

## Deliverables (both required)

1. **`/app/lib/wickkit.py`** — the repaired library, with every defect
   corrected strictly via accepted patchdeck requests.
2. **`/app/tools/patchdeck.log`** — the attempt log showing all five findings
   applied within the 5-attempt budget.

## Verification

The verifier audits `/app/tools/patchdeck.log` against the audit report
(budget, one applied request per finding, and cryptographic ties between each
logged request and the delivered file's lines), then re-tests every function
of the delivered `/app/lib/wickkit.py` on hidden vectors derived from the
docstring contracts. Repairs must hold on **any** inputs satisfying the
contracts, not just the selfcheck vectors.

## Do NOT modify

`/app/tools/patchdeck.py` and `/app/audit/findings.json` are read-only
infrastructure; tampering with them (or with the log by hand) fails the run.
No network access is needed or available at verify time.
