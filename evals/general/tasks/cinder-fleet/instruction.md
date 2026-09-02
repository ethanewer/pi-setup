# Recover the gate-controller secret from a firmware dump

You are handed a firmware dump from a parking-gate controller in
`/app/workspace`. The vendor PIN that protects the service token is not stored
anywhere in the clear — it must be recovered from the dump itself. Your job is
to build **one reusable Python tool**, `/app/extract.py`, that recovers
everything from any conforming dump, and to run it on `/app/workspace` so the
recovered secret is persisted under `/app` with the **expected
normalization**. All artifacts are byte-checked by a verifier that also
re-runs your tool on fresh hidden dumps.

## Scenario contents (`/app/workspace/`)

- `dump.bin` — the firmware blob, a flat sequence of **TLV records**. Each
  record is: 1 byte tag, 1 byte length `L` (0–255), then `L` payload bytes.
  The tag byte is the record type; `L` counts payload bytes only.
- `README.txt` — flavor text (no key material).

### Tag table

| tag | meaning |
|-----|---------|
| `0x01` | `META` — ASCII device info; ignore. |
| `0x02` | `NONCE` — ASCII digits; ignore. |
| `0x05` | `NOISE` — random bytes; ignore. |
| `0x06` | `DECOY` — XOR'd legacy junk; ignore. |
| `0x03` | `TOKEN` — payload is the service token **XOR-encoded with the 4-ASCII-digit PIN** (the PIN bytes repeat cyclically over the payload). |
| `0x04` | `CRC32` — 4 bytes, **little-endian** `crc32` (as computed by `zlib.crc32`) of the **decoded** token payload (the raw ASCII payload, before any normalization). |

## How to recover the PIN

Brute force it: the PIN is exactly 4 ASCII digits (`"0000"`–`"9999"`). For a
`TOKEN` payload `P` and candidate PIN bytes `K`, the decode is
`plain[i] = P[i] ^ K[i % 4]`. The correct PIN is the one whose decoded payload
is printable ASCII **and** whose `zlib.crc32` equals one of the `CRC32`
records in the dump. This matters because a dump may contain **decoy
`TOKEN`/`CRC32` pairs** whose CRC never validates — only the pair that passes
the CRC check is real. `CRC32` records may appear **before or after** their
`TOKEN` record; do not assume order.

## Deliverables (all four required)

1. `/app/extract.py` — your reusable tool (it is itself a deliverable). CLI:
   ```
   python3 /app/extract.py <workspace_dir> <out_dir>
   ```
   It reads `<workspace_dir>/dump.bin` and writes into `<out_dir>`:
   - `secret.txt` — the recovered service token with the **expected
     normalization**: all **lowercase**, **no leading or trailing whitespace**
     (whitespace inside the payload around the token must be stripped), a
     single trailing newline is allowed. E.g. a decoded payload
     `" GRAVITY-OWL-42 "` must be persisted as `gravity-owl-42`.
   - `pin.txt` — the recovered PIN as exactly 4 digits (zero-padded), one
     line.
   - `records.json` — a JSON object:
     ```json
     {
       "records": [{"tag": "01", "length": 33}, ...],
       "pin": "8314",
       "secret": "gravity-owl-42"
     }
     ```
     `records` lists **every** record of `dump.bin` in file order (tags as
     two lowercase hex digits, `length` as the payload byte count). If a
     record is truncated at end-of-file, stop parsing there.

2. `/app/secret.txt`, `/app/pin.txt`, `/app/records.json` — the outputs of
   running your tool on the shipped workspace:
   ```
   python3 /app/extract.py /app/workspace /app
   ```

All artifacts must be produced by **running** your tool — do not hand-edit
them.

## What is checked

- `/app/extract.py` is re-run unchanged on hidden dumps with a **different
  PIN, token, noise, decoys, and record ordering** — it must be generic.
- `secret.txt` must match the expected token under the exact normalization
  above (stray whitespace, uppercase, or altered values fail the exact
  match). Payloads may carry leading/trailing spaces around the token.
- `pin.txt` must be the correct zero-padded 4-digit PIN.
- `records.json` must mirror the dump's record table exactly (every record,
  in order, correct tag and payload length) and carry the correct
  `pin`/`secret` values.
- `/app/secret.txt`, `/app/pin.txt`, `/app/records.json` must be identical to
  a fresh run of your tool on `/app/workspace`.

## Constraints

- Work only under `/app`; never read `/tests` or `/solution`.
- Do not modify the fixtures in `/app/workspace`.
- Standard library only; no network access.
