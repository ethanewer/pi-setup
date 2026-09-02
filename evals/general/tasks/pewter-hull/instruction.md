# Fragment the acoustic uplink payload

The benthic observatory's acoustic uplink can only carry **frames of at most
`CAP` bytes** each, so oversized files must be fragmented into a numbered,
recoverable frame set with a manifest — and reassembled byte-for-byte on the
far side. Build the framer tool and run it once on the visible payload.

Working directory: `/app`. Python 3.12 is available as `python3`; standard
library only, no network.

## Visible inputs (do not modify them)

* `/app/uplink/payload.bin` — the raw file to fragment.
* `/app/uplink/cap.txt` — plain text holding the frame byte cap `CAP`
  (an integer).

## Deliverables (both required)

### 1. `/app/framer.py`

Plain Python 3, stdlib only, with this interface:

```
python3 /app/framer.py split INPUT CAP OUT_DIR
python3 /app/framer.py join  OUT_DIR OUTPUT
python3 /app/framer.py audit OUT_DIR
```

**Frame file layout** — every frame file is at most `CAP` bytes and is
exactly:

| offset | size | field |
|-------:|-----:|-------|
| 0 | 4 | magic, the ASCII bytes `FRM1` |
| 4 | 4 | frame index, 0-based, big-endian unsigned 32-bit |
| 8 | 4 | total frame count `K`, big-endian unsigned 32-bit |
| 12 | 4 | payload length `P`, big-endian unsigned 32-bit |
| 16 | `P` | payload bytes |

So each frame carries `CAP - 16` payload bytes. Frame files are named
`frame_0000.frag`, `frame_0001.frag`, ... (zero-padded to width 4,
ascending). Every frame is exactly `CAP` bytes **except the last**, which
holds `min(CAP, remaining)` bytes — so every frame file is at most `CAP`
bytes.

**`split INPUT CAP OUT_DIR`**

* `CAP` must be an integer `>= 17` (16-byte header plus at least one payload
  byte). On a bad `CAP` (non-integer or too small) print a clear error to
  stderr and exit non-zero **without writing anything**.
* If `INPUT` does not exist (or is not a regular file), print
  `framer: no such file: <INPUT>` to stderr and exit non-zero.
* On success create `OUT_DIR` (making parents as needed), write the frame
  files, and write `OUT_DIR/manifest.json`:
  ```json
  {
    "magic": "FRM1",
    "input": "<INPUT basename>",
    "size": <input size in bytes>,
    "cap": <CAP>,
    "header_size": 16,
    "frames": <K>,
    "payload_per_frame": <CAP - 16>,
    "frame_files": ["frame_0000.frag", ...],
    "sha256": "<sha256 hex of the whole INPUT>",
    "frame_sha256": ["<sha256 hex of each full frame file>", ...]
  }
  ```
  where `K == ceil(size / (CAP - 16))` for a non-empty input, and `K == 0`
  with empty `frame_files` for an **empty input** (join must then produce an
  empty OUTPUT). Overwrite stale frames/manifest from any previous run in
  `OUT_DIR`.

**`join OUT_DIR OUTPUT`**

* Read `OUT_DIR/manifest.json` (missing/unreadable/unknown-magic manifest:
  error to stderr, exit non-zero, write nothing).
* Validate every frame file: it exists, is at most `CAP` bytes, starts with
  the `FRM1` magic, its header index/count/payload-length fields are
  consistent with the manifest and its position, and its full-file sha256
  matches `frame_sha256`.
* Only after **all** frames validate, concatenate the payloads, check the
  total length equals `size` and the sha256 equals `sha256`, and write the
  bytes to `OUTPUT` (overwrite if present). Any integrity failure: clear
  error to stderr, non-zero exit, and **OUTPUT must not be created**.
* Reassembling a split of a file must reproduce the original bytes exactly
  (the round trip must be lossless).

**`audit OUT_DIR`**

* Perform exactly the same validation as `join` (without writing anything)
  and print `AUDIT_OK frames=<K> size=<S> sha=<sha256 hex>` and exit 0 when
  everything checks out; on any failure print the problem to stderr and exit
  non-zero.

### 2. `/app/frames/` — the visible split result

Produce the frame set for the visible payload by actually running your tool:

```
python3 /app/framer.py split /app/uplink/payload.bin "$(cat /app/uplink/cap.txt)" /app/frames
```

`/app/frames/manifest.json` and the frame files must be the genuine output
of your `framer.py` on those inputs.

## Hidden probes the grader will run

The verifier runs **your `framer.py` unchanged** on inputs you have not
seen, so it must be general, not hard-coded:

* several `(INPUT, CAP)` combinations, including a single-frame file, an
  exact multiple of the payload size, a large multi-frame file, and an
  **empty input** (`K == 0`, join produces an empty file);
* per-frame checks: every frame file at most `CAP` bytes, correct magic and
  big-endian header fields, sizes exactly per the framing rule;
* `audit` succeeding on every valid split; `join` round trips reproducing
  every original byte;
* a **corrupted frame set** (a tampered frame payload): both `join` and
  `audit` must exit non-zero, and `join` must not create its OUTPUT;
* bad invocations: nonexistent input, `CAP` too small (`<= 16`), non-integer
  `CAP` — all must exit non-zero without creating the output directory.

## Constraints

* Do not modify `/app/uplink/payload.bin` or `/app/uplink/cap.txt`.
* Standard library only; deterministic; no network.

## Self-check

```
python3 /app/framer.py split /app/uplink/payload.bin "$(cat /app/uplink/cap.txt)" /app/frames
python3 /app/framer.py audit /app/frames
python3 /app/framer.py join /app/frames /tmp/roundtrip.bin
cmp /app/uplink/payload.bin /tmp/roundtrip.bin && echo "round trip ok"
```
