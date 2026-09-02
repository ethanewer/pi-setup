# Fume Latch — apply the per-line repair order against the fix desk

The **Fume Latch** repair desk holds a defective *latch plate* file in memory
and only accepts repairs through its HTTP API. An inspection round produced a
**work order**: one explicit fix request per defective line, each giving the
exact replacement content. Your job is to submit **exactly one fix request for
each located line**, in any order, and commit — while staying inside the
session's **fix budget**. The budget equals the number of work-order entries:
every accepted fix request consumes one unit, and a single request beyond the
budget permanently fails the session (`status: "budget-exceeded"`). Do not
retry, do not re-fix lines, do not "fix defensively".

## Provided files under `/app` (do NOT modify any of them)

- `/app/desk_service.py` — the repair-desk HTTP service (read-only; the
  verifier runs fresh copies of it).
- `/app/plate.txt` — the visible defective plate file. The service is the only
  writer: it loads the file into memory at startup and writes the repaired
  plate back at commit time. Editing it by hand does nothing useful.
- `/app/work_order.json` — the per-line repair requests:
  ```json
  {"order_id": "WO-4471", "file": "/app/plate.txt", "fixes": [
      {"line": 8, "content": "<exact new line>", "reason": "..."}, ...]}
  ```
  Lines are **1-based**. The `reason` is informational; `content` must be sent
  verbatim. A work order may contain a redundant entry for a line that is
  already correct — it still counts against the budget and must still be sent.
- `/app/desk/visible_case.json` — the visible session descriptor.

## The service contract

Start the visible session yourself:
```
python3 /app/desk_service.py --serve --port 8471 --case /app/desk/visible_case.json
```
JSON API on `127.0.0.1:<port>`:

- `GET /api/session` → `{"session", "lines", "budget", "fixes_used", "status"}`
- `GET /api/integrity` → `{"integrity": [<bool per line>], "all_fixed": <bool>}`
  (read-only self-check; it costs nothing)
- `POST /api/fix` body `{"line": <1-based int>, "content": "<exact new line>"}`
  → `200 {"ok": true, "line", "fixes_used", "budget"}`. Malformed bodies or
  out-of-range lines get `400` and consume nothing. A fix request when the
  budget is spent gets `409` and flips the session to `"budget-exceeded"`
  permanently — that fails the run.
- `POST /api/commit` → the receipt:
  `{"session", "all_fixed", "fixes_used", "budget", "status", "sha256",
  "mismatched_lines"}`. Committing **never** consumes budget; it writes the
  in-memory plate back to the workfile.

## Deliverables (both required)

1. **`/app/apply_fixes.py`** — a reusable repair client, runnable as:
   ```
   python3 /app/apply_fixes.py --url http://127.0.0.1:<port> \
       --order <work_order.json> --receipt <out_json>
   ```
   It must read the work order, submit exactly one `POST /api/fix` per entry
   (in work-order order), then `POST /api/commit`, and write the receipt. It
   must work against ANY desk session following this contract — the verifier
   runs it against fresh hidden sessions on other ports, so never hard-code
   the visible order, port, or plate contents.

2. **`/app/receipt.json`** — the receipt your client obtained for the visible
   session, written as a JSON object containing at least the commit response
   fields (`session`, `all_fixed`, `fixes_used`, `budget`, `status`, `sha256`)
   plus `"order_id"`. For the visible session a correct run has
   `all_fixed: true`, `status: "open"`, and `fixes_used: 4` of budget 4.

## Success check (what the grader enforces)

For every session (visible and hidden), ALL of the following must hold:

- the client exits 0 and produces a parseable receipt;
- `receipt.all_fixed` is `true` and `receipt.status` is `"open"` (a
  `budget-exceeded` session is an automatic fail — too many fix attempts);
- `fixes_used <= budget`, with budget set exactly to the number of work-order
  entries;
- the plate file after commit matches the expected content byte-for-byte
  (final newline included), and `receipt.sha256` matches its SHA-256.

## Edge cases the hidden sessions probe

- Work orders listed in arbitrary (e.g. descending) line order.
- Plates with or without a trailing newline; lines containing double spaces
  that must be repaired exactly as given.
- A redundant work-order entry for an already-correct line (still must be
  sent; budget sized to include it).
- Single-defect and multi-defect sessions.

## Constraints

- Work only under `/app`. Never read or depend on `/tests` or `/solution`.
- Standard library only; no network beyond `127.0.0.1` loopback HTTP.
- Do not modify `/app/desk_service.py`, `/app/plate.txt`,
  `/app/work_order.json`, or `/app/desk/*`.
