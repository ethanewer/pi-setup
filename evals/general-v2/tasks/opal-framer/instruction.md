# Frame the firmware freight payloads

The Halcyon Relay freight network moves firmware images over a transport whose
frames can carry at most `CAP` bytes each. An oversized image must be
**fragmented** into frames that each fit within the cap, and later
**reassembled** byte-exactly — with every frame checksum-verified so a corrupted
frame is detected instead of silently reassembled. All work happens under
`/app`. Leave behind exactly the deliverables listed below.

## What is provided in the environment

* `/app/image.bin` — the visible firmware image (raw bytes) you must frame.

## Deliverables (create all three; nothing else is graded)

### 1. `/app/framer.py`

A plain Python 3 program (stdlib only) with this interface:

```
python3 /app/framer.py pack INPUT OUT_DIR CAP
python3 /app/framer.py unpack OUT_DIR OUTPUT
```

#### `pack INPUT OUT_DIR CAP`

* Read `INPUT` as raw bytes. If `INPUT` does not exist (or is not a regular
  file), print a clear error to **stderr** and exit non-zero **without writing
  anything**.
* `CAP` must be a positive integer (`CAP >= 1`). If `CAP` is missing, not an
  integer, or `< 1`, print a clear error to stderr and exit non-zero without
  writing anything (do **not** create `OUT_DIR` in these failure cases).
* On success, create `OUT_DIR` if needed and write one frame per split:
  `frame_00000.bin`, `frame_00001.bin`, ... (zero-padded to **width 5**,
  ascending). Frame `i` holds the bytes of `INPUT` at offsets
  `[i*CAP, min((i+1)*CAP, size))`, so every frame is at most `CAP` bytes and
  every frame except the last is exactly `CAP` bytes. An empty input produces
  **zero** frame files.
* Also write `OUT_DIR/index.json` (overwrite on re-pack) recording the inverse
  mapping, with exactly this shape:

  ```json
  {
    "input": "<basename of INPUT>",
    "size": <input size in bytes>,
    "cap": <CAP>,
    "frames": <number of frames>,
    "sha256": "<lowercase hex sha256 of the whole input>",
    "parts": [
      {"name": "frame_00000.bin", "offset": 0, "length": <n>,
       "sha256": "<lowercase hex sha256 of that frame's bytes>"},
      ...
    ]
  }
  ```

  `frames == ceil(size / CAP)`; the `parts` array has exactly `frames` entries
  in ascending offset order (empty for an empty input).

#### `unpack OUT_DIR OUTPUT`

* Read `OUT_DIR/index.json`. For each entry of `parts`, in order:
  * the frame file `OUT_DIR/<name>` must exist, have exactly `length` bytes and
    a sha256 equal to the recorded `sha256`;
  * on any mismatch (missing file, wrong length, wrong digest, malformed
    manifest, or final assembled digest != the recorded whole-input `sha256`),
    print a clear error containing the word `corrupt` to stderr, exit
    non-zero, and do **not** write `OUTPUT`.
* Otherwise write the concatenated frame bytes (exactly `size` bytes) to
  `OUTPUT`, overwriting it if present. Reassembling a pack of a file must
  reproduce the original bytes exactly.

### 2. `/app/payload/index.json`

The manifest produced by running:

```
python3 /app/framer.py pack /app/image.bin /app/payload 1000
```

(the corresponding `frame_*.bin` files must sit next to it in `/app/payload`).

### 3. `/app/reassembled.bin`

The result of running:

```
python3 /app/framer.py unpack /app/payload /app/reassembled.bin
```

It must be byte-identical to `/app/image.bin`.

## Constraints

- Work under `/app` only. Do not modify `/app/image.bin`.
- `/app/framer.py` must use only the Python standard library.
- The verifier re-runs `/app/framer.py` on hidden inputs (different sizes, caps
  that are non-multiples, exact multiples, larger than the input, empty inputs,
  invalid caps, missing inputs, and corrupted frames) — it must be general and
  parameterized exactly as specified above, not hard-coded to the visible
  fixture.
- Match the exact command names (`pack`/`unpack`), argument order, frame-name
  width, and manifest keys above.

## What "done" looks like (self-check commands)

```
python3 /app/framer.py pack /app/image.bin /app/payload 1000
python3 /app/framer.py unpack /app/payload /app/reassembled.bin
cmp /app/image.bin /app/reassembled.bin && echo "round trip ok"

# corrupted frame must be detected
python3 /app/framer.py pack /app/image.bin /tmp/chk 700
printf 'X' | dd of=/tmp/chk/frame_00000.bin bs=1 seek=3 conv=notrunc
python3 /app/framer.py unpack /tmp/chk /tmp/chk_out; echo "exit=$?"
```
