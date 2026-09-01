# Probe the depot slot registry over its socket protocol

The fulfilment depot runs **slotd**, a raw TCP text service on loopback that
maps slot coordinates to stored parts. You must build a probe client that
drives the service's request/response protocol and summarises what it finds.

## Environment

- Working directory: `/app`. The service fixture lives under `/app/registry/`:
  - `/app/registry/slotd.py` — the service (read it; the wire protocol is in
    its top docstring and fully restated below).
  - `/app/registry/table.json` — the slot table the service serves.
  - `/app/registry/manifest.txt` — the list of slots to probe.
- Start the service yourself on loopback, port **47331**:
  ```
  python3 /app/registry/slotd.py /app/registry/table.json 47331
  ```
- Python 3.12 is available as `python3`; standard library only, no network
  beyond loopback.

**Do not modify anything under `/app/registry/`** — those files are the
service you must interoperate with.

## The slotd protocol (strict single-request-per-turn)

The server handles **exactly one request per TCP connection**: connect, write
one request line, read one JSON response line, and the server closes the
connection. A second request written on the same connection is silently lost —
never pipeline.

Requests and responses:

- `PING` → `{"ok":true,"kind":"pong","slots":<int>}`
- `SLOT <zone>/<row>/<bay>` (e.g. `SLOT A/1/01`) →
  - key present: `{"ok":true,"kind":"slot","slot":"A/1/01","zone":"A","row":1,"bay":1,"sku":"<str>","qty":<int>,"token":"<16hex>"}`
  - well-formed key not in the table: `{"ok":false,"kind":"error","error":"unknown-slot"}`
- Anything else: `{"ok":false,"kind":"error","error":"bad-request"}`

A slot's `token` is deterministic: `sha256("slotd-v1:" + <slot key>)`
truncated to 16 lowercase hex chars. It depends only on the key.

## Deliverables (both required)

1. `/app/probe.py` — a runnable Python program with this interface:
   ```
   python3 /app/probe.py <host> <port> <manifest_file> <output_json>
   ```
   It reads the manifest, queries the service **one request per connection**
   for each probeable line, and writes the summary JSON to `<output_json>`.
   It must work on any manifest/table pair conforming to the contract below,
   not just the provided files.

2. `/app/summary.json` — the summary your program produces **when run against
   the provided table on port 47331**:
   ```
   python3 /app/probe.py 127.0.0.1 47331 /app/registry/manifest.txt /app/summary.json
   ```

## Manifest format

Newline-separated text. Each line is one of:

- **Probe line:** `SLOT <zone>/<row>/<bay>` where `<zone>` is 1–8 uppercase
  letters `[A-Z]{1,8}` and `<row>`/`<bay>` are decimal integers
  (`^[A-Z]{1,8}/[0-9]+/[0-9]+$`). Leading/trailing surrounding whitespace is
  allowed.
- **Comment:** a line whose first non-space character is `#`.
- **Blank lines** (only whitespace).
- **Malformed lines:** anything else (wrong verb, lowercase zone, missing
  part, free text, `SLOT` with no key, …). Malformed lines are **skipped and
  never sent** to the service.

Duplicate probe lines are **idempotent**: a slot queried twice counts once.

## Required output JSON

Exactly these keys:

```json
{
  "ok_slots": ["A/1/01", ...],
  "unknown":  ["D/9/99", ...],
  "tokens":   {"A/1/01": "<16hex>", ...},
  "total_qty": <int>,
  "heaviest": {"slot": "...", "sku": "...", "qty": <int>, "token": "<16hex>"}
}
```

- `ok_slots` — the **sorted** (lexicographic) list of distinct probe keys the
  service answered with `ok:true`.
- `unknown` — the sorted list of distinct probe keys that were well-formed
  but returned `unknown-slot`.
- `tokens` — the service token for every entry of `ok_slots` (same keys).
- `total_qty` — the sum of `qty` over the distinct ok slots.
- `heaviest` — the ok slot with the **maximum `qty`**; on a tie the
  lexicographically **smallest** slot key wins; its `sku`, `qty` and `token`
  are echoed from the service response. If there are no ok slots it must be
  `null`.

## Edge cases the grader will exercise (hidden manifests + hidden tables)

The grader boots a **fresh slotd** on unseen tables and runs your program on
unseen manifests. It must handle all of these correctly:

- Empty probe set (manifest with only comments/blanks/malformed lines):
  `ok_slots`, `unknown`, `tokens` all empty, `total_qty` 0, `heaviest` null.
- A table where two slots tie for maximum `qty` (tie-break: smallest key).
- Slots with `qty` 0, and a manifest where the max-qty slot is only reachable
  through duplicates.
- Many `unknown-slot` replies mixed with ok replies.
- Malformed manifest lines that must never reach the service.

## Constraints

- The verifier runs your program **unchanged** (via `python3 /app/probe.py`)
  against fresh service instances and hidden inputs, so do not hard-code the
  provided table, manifest, or port — read everything from the arguments.
- One request per connection; the server ignores anything pipelined.
- Do not modify `/app/registry/`. `/tests` and `/solution` are not available
  to you.
