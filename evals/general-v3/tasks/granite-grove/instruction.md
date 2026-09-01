# Granite Grove — office automation pipeline

You are automating routine office tasks at **Granite Grove**, a co-working hub.
You must write a single Python pipeline program `/app/solve.py` and run it so
that it produces `/app/answer.json`. The pipeline is tested on the provided
**primary** case in `/app/data` and on several **hidden** cases (with the same
layout but different people, schedules, and transactions), so it must be
**general**: it must discover inputs, never hard-code names or numbers, and
always work from the case directory it is given.

Your deliverables are:
- `/app/solve.py` — the pipeline program.
- `/app/answer.json` — result of running your pipeline on the primary case.

### How the pipeline is invoked

The verifier (and you, locally) run it like this:

```
python3 /app/solve.py --case <CASE_DIR> [--url <http://127.0.0.1:PORT>] --out <RESULT_JSON>
```

- `--case`  : a directory (the primary case is `/app/data`). Required.
- `--url`   : the base URL of a **live** schedule service that is already
  running. If omitted, your pipeline must start the service itself (see below).
- `--out`   : path where the summary JSON (`answer.json`) is written.

Because the verifier starts fresh schedule services and passes a fresh `--url`
to you for every case (including hidden ones), your pipeline must be written to
**fetch over HTTP**, never to read/copy pre-existing calendar files.

## Case layout

Every case directory contains exactly:

```
<CASE_DIR>/
  calendar/service_config.json     schedule service config (people, token)
  availability/availability.csv    availability slots (one line per slot)
  ledger/ledger.json               parties and their current balances
  ledger/items.json                items with owner + price
  ledger/transfer.json             one proposed transfer
  ledger/transfer_log.json         append-only log of past transfers
```

## Part 1 — Calendar schedule files (fetch fresh calendars)

`/app/tools/schedule_service.py` is an HTTP server with these endpoints:

- `GET /health`                          -> 200 "ok" (no auth needed)
- `GET /person/<key>.ics`                -> the person's live calendar (200)

Every calendar request **must** carry header `X-Auth-Token: <token>`. The token
is `service_config.json["auth_token"]`. Unauthenticated `/person/*` requests
get `403`.

The config also lists people as `service_config.json["people"]`, an array of
objects each with `"key"` and `"display"`. Fetch **every** person listed in the
config (people may number 0..N with no slots). Save the body of each
`/person/<key>.ics` to `<CASE_DIR>/out/<key>.ics`.

Freshness rule: each served calendar embeds a random, per-process
`X-GROVE-SESSION` id that exists **only in a running service process**. A
calendar written by hand or copied from disk will never match a freshly served
one. Therefore your pipeline must actually request the service (per starter
temp file) — hard-coding calendar content is the main failure mode.

When `--url` is given, use it directly. When it is omitted, launch the service
yourself:

```
python3 /app/tools/schedule_service.py --config <CASE_DIR>/calendar/service_config.json --port 0 --outdir <DIR>
```

and read its `GRANITE_GROVE_UP port=NNNN` line from stdout to discover the real
port, then set `base_url = http://127.0.0.1:<port>` for your requests. Wait for
`/health` to respond before fetching. A person with `"slots": []` still yields
a valid (empty) ics that you must save.

## Part 2 — Overlap finder

`/app/tools/find_overlaps.py` is a ready-made tool. Drive it (a subprocess) with
the availability CSV as its single argument:

```
python3 /app/tools/find_overlaps.py <CASE_DIR>/availability/availability.csv
```

It prints a JSON array of overlaps to stdout. Capture that stdout and write it
verbatim (it is already valid JSON) to `<CASE_DIR>/out/overlaps.json`. Do NOT
re-implement overlap logic; invoke the provided tool.

Notes on the tool's behavior you must respect (also how hidden cases are graded):
- A row is skipped unless it has a non-empty `slot_id`, `person`, and a
  recognized `day` (`Mon..Sun`), a parseable `start`/`end` of the form `HH:MM`
  (24h), and `end > start`. Malformed rows (blank times, bad day names,
  zero-length windows) are dropped silently.
- Each within-day pair of slots from different people contributes one result if
  they overlap by **more than 1 minute** (`max(start) < min(end) - 1`).
- Result objects: `{"person": [<personA>, <personB>] (sorted), "day",
  "overlap_start": "HH:MM", "overlap_end": "HH:MM", "minutes": N}`.
- Sorted by `minutes` desc, then by weekday order (Mon..Sun), then person labels.

## Part 3 — Validate and transfer rule

This is business logic you implement yourself. Read four files under
`<CASE_DIR>/ledger/`:

- `ledger.json`       -> `{"parties": {<key>: {"label": ..., "balance": ...}}`
- `items.json`        -> `{<item_id>: {"name": ..., "owner": <key>, "price": <int>}}`
- `transfer.json`     -> `{"item": <id>, "seller": <key>, "buyer": <key>, "amount": <int>}`
- `transfer_log.json` -> list of past entries `{"item","from","to","amount"}`

Rule (apply in this order; stop at the first failing condition):
1. Reject if `buyer == seller`                -> reason `"buyer and seller are the same party"`.
2. Reject if `buyer` not in `parties`         -> `"buyer is not a known party"`.
3. Reject if `seller` not in `parties`        -> `"seller is not a known party"`.
4. Reject if `item` not in `items`            -> `"item does not exist"`.
5. Reject if that item's current `owner != seller` -> `"seller does not own the item"`.
6. Reject if `amount <= 0`                    -> `"amount must be positive"`.
7. Reject if `buyer` balance `< amount`       -> `"buyer has insufficient funds"`.

If it survives all checks the transfer is **approved**, and **all** of these
side effects occur (in this order):
- debit: `parties[buyer].balance -= amount`
- credit: `parties[seller].balance += amount`
- reassign: `item.owner = buyer`
- append one log entry `{"item": <id>, "from": <seller>, "to": <buyer>, "amount": <amount>}`
  at the **end** of `transfer_log.json`'s list.

If any check fails the transfer is **rejected** and `ledger`, `items`, and the
log are left completely unchanged.

Write the resulting state to `<CASE_DIR>/out/transfer_out.json`:
```
{
  "approved": <true|false>,
  "reason": <null | "exact reason string">,
  "balances": {<party>: <int>, ...},                 // all parties, after
  "items":    {<id>: {"name","owner","price"}},       // all items, after
  "log":      [ ...entries with appended one if approved... ]
}
```

## Result summary

Write `<RESULT_JSON>` (the value of `--out`) as:
```
{
  "pipeline": "granite-grove",
  "calendar": {"status": "ok", "files": ["<key>.ics", ...]},
  "overlaps_count": <int>,
  "transfer": {"status": "approved"|"rejected", "reason": null|<string>}
}
```

`calendar.files` lists the `<key>.ics` files you fetched (matching the order of
people in the config). `calendar.status` is `"ok"` when every person's calendar
was fetched.

## Constraints

- Do not modify anything under `/app/` other than creating `/app/solve.py`, writing
  `/app/answer.json`, and writing into `<CASE_DIR>/out/` for your chosen case.
- Do not edit `/app/tools/schedule_service.py` or `/app/tools/find_overlaps.py`.
- Keep numeric balances exact — the verifier compares your state to an exact
  reference, so avoid floating-point and preserve the declared JSON key structure.
- Your pipeline must generalize: hidden cases have different tokens, venue names,
  people, base dates, availability rows (including malformed ones), and transfers
  (including rejected ones).

## Acceptance

The verifier executes `/app/solve.py` on the primary case and on hidden cases
(fresh services, fresh dates), then checks: (a) every fetched `<key>.ics`
byte-matches a live-served calendar; (b) `out/overlaps.json` equals the overlap
tool's own output; and (c) `out/transfer_out.json` equals the reference
validate-and-transfer result. Produce all three outputs for every case.