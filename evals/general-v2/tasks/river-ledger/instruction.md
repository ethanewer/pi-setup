# Reconcile an append-only event journal

You are building a ledger reconciler. An append-only event journal lives at
`/app/events.jsonl` (one JSON record per line). Write a **Python program**
`/app/solve.py` that replays the journal and produces two deliverables:
`/app/state.json` (final per-account balances) and `/app/audit.jsonl`
(notable events). The program must obey the exact contract below, because it is
run **by an external checker on other journals it supplies** — not just your
output files.

## Deliverables (the checker executes these)

1. `/app/solve.py` — a Python script implementing the contract. Must be
   self-contained (only uses the standard library, which is enough).
2. `/app/state.json` — result of running the program on `/app/events.jsonl`.
3. `/app/audit.jsonl` — result of running the program on `/app/events.jsonl`.

Run the program yourself so the two output files reflect its real behaviour.

## CLI contract

`python3 /app/solve.py [INPUT] [STATE_OUT] [AUDIT_OUT]`

- No arguments -> `input=/app/events.jsonl`, `state=/app/state.json`,
  `audit=/app/audit.jsonl`.
- With three arguments, the program reads the journal at the given `INPUT` path
  and writes JSON state and JSON-lines audit to `STATE_OUT` and `AUDIT_OUT`.
- The checker invokes the 3-argument form on hidden/journal files and compares
  the written files. It also invokes the 0-argument form and compares
  `/app/state.json` and `/app/audit.jsonl`. Your program MUST therefore be
  correct on arbitrary new journals, not just the one in `/app/events.jsonl`.

## Input format

Each line of the journal is one of:
- a valid JSON object `{"id": "...", "account": "...", "delta": <number>}`,
  optionally with `"correction": true`;
- a JSON value that is not an object (e.g. `[1,2,3]` or a bare string/number);
- an object missing one or more of `id`, `account`, `delta`;
- a line that is not valid JSON at all;
- a blank/empty line (a line with only whitespace);
- a record whose `delta` is not a number (e.g. a string).

## Semantics (applied strictly in file order)

Line numbers are **1-indexed**.

1. **Skip** blank/whitespace-only lines entirely.
2. **Malformed** lines (any of: not JSON, JSON but not an object, missing
   `id`/`account`/`delta`, or a non-numeric `delta`) do NOT stop the replay.
   Record `{"kind": "malformed", "line": <lineno>}` in the audit and continue.
3. **Duplicate IDs.** Once an `id` has been seen (whether it was a normal event
   or a correction), any later record carrying the SAME `id` is ignored: it does
   not change any balance and no correction is applied for it. Record
   `{"kind": "duplicate", "id": <id>}` and continue.
4. **Normal event.** A non-duplicate event without `"correction": true` adds its
   `delta` to that account's balance.
5. **Correction event.** A non-duplicate event with `"correction": true`
   **resets** that account's balance to `0` first, then adds this event's
   `delta`. It also records `{"kind": "correction", "id": <id>}` in the audit.
   (A correction on an account not seen before is just a reset of 0 plus delta.)
6. Deltas may be positive, negative, zero, integer or fractional.

## Output formats

`/app/state.json` — a single JSON object mapping each account name to its final
numeric balance. Account order does not matter for grading (the checker
compares the objects), but sorting them is clean and deterministic.

`/app/audit.jsonl` — one compact JSON object per line, IN the order the events
were encountered, e.g.:

```
{"kind": "duplicate", "id": "e1"}
{"kind": "malformed", "line": 4}
{"kind": "correction", "id": "e3"}
```

Only duplicate / malformed / correction events appear here; plain events are
not listed. Every audit line is wrapped in `{}` and on its own line.

## Visible example

`/app/events.jsonl`:
```
{"id":"e1","account":"alpha","delta":10}
{"id":"e2","account":"beta","delta":5}
{"id":"e1","account":"alpha","delta":100}
not-json
{"id":"e3","account":"alpha","delta":-3,"correction":true}
```

Trace:
- line 1 `e1`: alpha = 10
- line 2 `e2`: beta = 5
- line 3 `e1`: duplicate of an already-seen id -> ignored, audit `duplicate:e1`
- line 4 `not-json`: malformed -> audit `malformed:4`
- line 5 `e3` correction: reset alpha to 0 then -3 -> alpha = -3, audit `correction:e3`

Expected `/app/state.json`:
```json
{ "alpha": -3, "beta": 5 }
```

Expected `/app/audit.jsonl`:
```jsonl
{"kind":"duplicate","id":"e1"}
{"kind":"malformed","line":4}
{"kind":"correction","id":"e3"}
```

## Constraints

- Do NOT modify, rename, delete, or hard-code the contents of the input files.
- Use only the Python standard library.
- The program must never read `/tests`, `/solution`, or any checker data.
- The program must exit cleanly (status 0) even when the journal contains
  malformed records.

## Hints on what hidden cases probe

Hidden journals exercise: duplicate IDs (including a duplicate of a correction
ID), correction events on existing and on brand-new accounts, empty/blank lines,
fully non-JSON and structurally-valid-but-invalid records, non-numeric deltas,
zero and floating-point deltas, and negative/positive balances. Follow the rules
precisely; a partial or single-case implementation will fail the hidden runs.