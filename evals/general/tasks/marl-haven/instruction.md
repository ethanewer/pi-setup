# Recover the sonar telemetry matrix from an SBT-1 capture

Deepwater acoustics group: a sonar buoy ("SBT-1") writes its recordings as a
custom **binary capture file**. A capture bundles fixed-size frames of
int16 channel samples, optionally delta-encoded, and some frames are marked
invalid by the firmware. Your job is to reverse the on-disk format and ship a
**runnable extraction script** that applies a frame/channel query to a capture
and persists the recovered matrix as a binary `.npy` file.

Work inside `/app`. **Do not modify** `/app/capture.bin` or `/app/query.txt`.
Write your own program files into `/app`.

## Environment

- Working directory: `/app`. It already contains the visible fixtures
  `/app/capture.bin` and `/app/query.txt`. Python 3.12 and `numpy` are
  available. No network at verify time.

## Capture file format (`capture.bin`, all integers big-endian)

The file is a 16-byte header followed by exactly `N` frames.

**Header (16 bytes):**

| offset | size | field |
|--------|------|-------|
| `[0:4]`  | 4 | magic — the bytes `S`, `B`, `T`, `F` (i.e. `b"SBTF"`) |
| `[4:6]`  | 2 | `version` — uint16, always `1` |
| `[6]`    | 1 | `key` — uint8 XOR key used to obfuscate frame payloads |
| `[7]`    | 1 | `flags` — uint8; bit 0 (value `1`) = payload is delta-encoded; other bits reserved `0` |
| `[8:12]` | 4 | `frame_count` `N` — uint32, number of frames that follow |
| `[12:14]`| 2 | `channel_count` `C` — uint16 |
| `[14:16]`| 2 | reserved — uint16, `0` |

**Each frame is exactly `9 + 2*C` bytes:**

| offset | size | field |
|--------|------|-------|
| `[0:8]`   | 8 | `timestamp_ms` — uint64 (present in every frame, but NOT used by the query logic) |
| `[8]`     | 1 | `status` — uint8; `1` = valid frame, `0` = invalid frame (firmware discarded it) |
| `[9:]`    | `2*C` | payload — raw bytes; **first XOR every payload byte with `key`**, then parse the result as `C` big-endian int16 samples (sample `c` occupies bytes `[2c:2c+2]` of the de-XORed payload) |

**Decoding to true values, per channel, across the sequence of VALID frames
(in file order):**

- If `flags` bit 0 is `0`: true value = the parsed sample.
- If `flags` bit 0 is `1`: the payload carries **deltas**. The true value of the
  first valid frame is its own delta; every later valid frame's true value is
  the previous valid frame's true value plus its delta (a cumulative sum over
  valid frames only — invalid frames are skipped and contribute nothing).
  Accumulate in a wide integer type (the true values are guaranteed to fit in
  int16, so an int16- or int64-wide accumulator both work).

Raw int16 samples may be negative.

## Query file format (`query.txt`)

Plain text with exactly two significant lines:

```
channels=<spec>
frames=<spec>
```

`<spec>` is a comma-separated list of tokens; each token is either a single
non-negative integer (`7`) or an inclusive range `a-b` (if `a > b` it is
normalized to `min(a,b)..max(a,b)`). Expansion rules:

- Tokens are processed **left to right**; each token contributes its indices in
  ascending order; duplicates are legal and honored (a repeated index produces
  a repeated column/row).
- The output **rows** follow the `frames` spec order exactly; the output
  **columns** follow the `channels` spec order exactly.
- Frame indices are positions (0-based) in the sequence of **valid frames
  only** — invalid frames are removed before indexing, so they do not consume
  an index.
- A frame index `>=` the number of valid frames is simply **ignored** (no
  error, no row).

## Deliverables (both required)

1. `/app/extract.py` — a runnable extraction program: executable bit set
   (`chmod +x`), first line shebang `#!/usr/bin/env python3`, CLI:

   ```
   python3 /app/extract.py <capture_file> <query_file> <out_npy>
   ```

   It decodes the capture, applies the query, and writes the recovered matrix
   to `<out_npy>` as a standard numpy `.npy` file (`numpy.save`) with
   **dtype float64** and shape `(num_selected_frames, num_selected_channels)`
   — rows are frames, columns are channels (an orientation flipped or
   transposed matrix is wrong). The grader runs this program unchanged on
   hidden captures/queries, so it must implement the full contract above, not
   the visible fixture contents.

2. `/app/payload.npy` — the matrix your program produces on the provided
   fixtures:

   ```
   python3 /app/extract.py /app/capture.bin /app/query.txt /app/payload.npy
   ```

## Edge cases the grader probes (your program must handle all of them)

- Delta-encoded captures (flags bit 0 set) and plain captures (bit clear),
  including `key = 0`.
- Invalid frames interleaved with valid ones — indexing skips them.
- Query indices listed out of order (rows/columns follow the query order, so a
  reversed channel list yields a matrix whose columns are reordered), ranges
  written reversed (`3-1`), and duplicate indices.
- Out-of-range frame indices ignored silently.
- A capture whose frames are **all** invalid: any frame query selects zero
  rows; the saved matrix must have shape `(0, num_selected_channels)` and must
  still be a valid `.npy` file.

## Constraints

- Standard library + `numpy` only; no network.
- Do not modify `/app/capture.bin` or `/app/query.txt`.
- The verifier re-executes `/app/extract.py` on hidden inputs and compares the
  saved matrices (shape, dtype, orientation, exact values).
