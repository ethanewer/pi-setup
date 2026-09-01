# Opal Marsh — size-capped calibration map

The Opal Marsh wetland array re-maps raw sensor ids to calibrated channel ids
through a fixed permutation. You must write the generator that emits the
calibration map **under both a row cap and a byte cap** — choosing between two
encodings — and refuse when the caps cannot be met.

Python 3.12 standard library only; no network access.

## Deliverables (all three required)

1. `/app/gen_map.py` — a runnable Python 3 program:

   ```
   python3 /app/gen_map.py <spec.json> [out_file] [--report-out PATH]
   ```

   - `<spec.json>` : the spec (schema below).
   - `[out_file]` : output map path; default `/app/calib_map.txt`.
   - `[--report-out PATH]` : report path; default `/app/map_report.json`.

2. `/app/calib_map.txt` — the map produced by running

   ```
   python3 /app/gen_map.py /app/spec.json
   ```

3. `/app/map_report.json` — the report produced by the same default run.

**Do not modify `/app/spec.json`.**

## The spec and the permutation

```json
{ "bits": 8, "a": 156, "r": 3, "cap_rows": 256, "cap_bytes": 2048 }
```

- `bits` — width `b` of the id space: sensor ids are `0 .. 2**b - 1` (always
  `4 <= b <= 12`).
- The calibration permutation is `dst = rotl(src XOR a, r)` where `rotl` is a
  circular left rotation by `r` (`0 <= r < bits`) on `bits`-wide words and
  `0 <= a < 2**bits`. Every id has exactly one dst, and the map is a bijection.
- `cap_rows` — the map file may contain **at most** this many mapping rows.
- `cap_bytes` — the map file may be **at most** this many bytes.

## The two encodings

Let `w = ceil(bits / 4)` be the fixed hex-field width (zero-padded, lowercase).
Every mapping row is exactly one line `srchex,dsthex` followed by `\n`
(so `2*w + 2` bytes per row).

**FULL encoding** — one row for every src, in increasing src order:

```
FULL
00,9c
01,a3
... (2**bits rows total)
```

Header line is `FULL\n` (5 bytes). Body rows: `2**bits`.

**SPARSE encoding** — the identity is the default. Header line is `SPARSE\n`
(7 bytes), followed by one row `srchex,dsthex` for **each src whose dst differs
from src** (the non-fixed points), in increasing src order. Any src not listed
maps to itself. (For the identity permutation the body is empty and the file is
just the 7-byte header.)

## What the program must do

1. Compute the full permutation from the spec.
2. Compute the exact byte size and row count of **both** encodings.
3. If **both** fit under `cap_rows` **and** `cap_bytes`, write the one with the
   smaller byte size (on a byte tie, write FULL).
4. If **only one** fits, write that one.
5. If **neither** fits: print a line starting with `INFEASIBLE` to **stdout**,
   exit with a **non-zero** exit code, and **do not create or modify** the
   output file.
6. When writing, also write the report JSON with exactly these keys:

```json
{ "mode": "FULL", "mapping_rows": 256, "file_bytes": 1541 }
```

`mode` is `"FULL"` or `"SPARSE"` (matching the file's header), `mapping_rows`
is the number of mapping rows actually written, and `file_bytes` is the exact
byte length of the written file. The verifier recomputes all three from the
file on disk and rejects contradictions.

## Edge cases the grader probes (hidden specs)

- A spec where **only the SPARSE encoding** fits (row cap below `2**bits`).
- A spec where the byte cap is **exactly** the FULL encoding's size — your byte
  arithmetic must be exact (`<=` is allowed, one byte over fails).
- The **identity permutation** (`a = 0, r = 0`), whose SPARSE encoding is a
  header-only file.
- An **infeasible** spec that must be refused: `INFEASIBLE` on stdout, non-zero
  exit, and no output file left behind.
- Caps that both encodings satisfy — the smaller one must be chosen.

The verifier re-runs your `/app/gen_map.py` unchanged on the visible and hidden
specs and independently re-validates the mapping, both caps, and the report.
