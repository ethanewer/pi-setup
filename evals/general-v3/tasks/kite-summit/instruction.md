# Kite Summit — bounded-size constructs

You are working in `/app` inside a Debian container (Python 3.12, numpy preinstalled).
Complete **all three** independent subtasks. Every deliverable is a real artifact that the
verifier will inspect and execute, so produce exactly the files and bytes described.
Read every format rule carefully — the verifier is strict and byte-exact.

The three deliverables that the grader runs are:

| subtask | deliverable(s) |
|---|---|
| 1. gate network | `/app/gate_net.txt`, `/app/gate_validate.py` |
| 2. compressor  | `/app/compress.py` (`/app/payload.bin` produced by it) |
| 3. footprint   | `/app/footprint_report.txt` |

Do not modify `/app/sample.dat`, do not delete it, and do not leave oversized caches in the
Python site-packages tree (see subtask 3).

---

## Subtask 1 — Gate network for isqrt-then-Fibonacci (`/app/gate_net.txt`, `/app/gate_validate.py`)

The function to implement, for every unsigned 32-bit input `x` (`0 <= x <= 2^32-1`):

```
s  = isqrt(x)          # largest integer s with s*s <= x
y  = F_s mod 2^32      # F_0 = 0, F_1 = 1, F_n = F_(n-1) + F_(n-2)
```

You must express `y` as a **finite operator network**: a straight-line sequence of node
definitions, each node computing a 32-bit operation from earlier nodes. This is a
combinational circuit graph, not a general-purpose program — there are **no loops, jumps,
or memory**. The verifier feeds the network 32-bit inputs chosen at random and over edge
cases, evaluates every node, and compares the output to the exact reference. Hidden
input files contain only values in the documented domain `0 <= x <= 2^32-1`, so your
validator and network do not need to handle values outside that range.

### Operator language

`/app/gate_net.txt` has this structure (exact names and order):

```
VERSION 1
BITS 32
NODES 600
OUTPUT <node_id>
# comment lines are ignored anywhere
<node_id> = IN
<node_id> = CONST <uint32>
<node_id> = ADD <a> <b>
<node_id> = SUB <a> <b>
<node_id> = MUL <a> <b>
<node_id> = SHL <a> <k>
<node_id> = SHR <a> <k>
<node_id> = AND <a> <b>
<node_id> = OR  <a> <b>
<node_id> = XOR <a> <b>
<node_id> = NOT <a>
<node_id> = MUX <c> <a> <b>
<node_id> = ULT <a> <b>
```

Semantics (all values are unsigned 32-bit integers, `mod 2^32` where indicated):

- `IN` copies the 32-bit input `x` into the node. Exactly one `IN` node exists.
- `CONST <v>`: the literal `0 <= v <= 4294967295`.
- `ADD`, `SUB`, `MUL`: result reduced `mod 2^32` (i.e. `(a+b)&0xffffffff`, `(a-b)&0xffffffff`, `(a*b)&0xffffffff`).
- `SHL <a> <k>` / `SHR <a> <k>`: shift by constant `0 <= k <= 31`; `SHL` keeps the low 32 bits.
- `AND`, `OR`, `XOR`, `NOT`: bitwise; `NOT` is the 32-bit complement.
- `MUX <c> <a> <b>`: `a` when `c != 0`, else `b`.
- `ULT <a> <b>`: `1` when unsigned `a < b`, else `0` (a Boolean as a 32-bit value).

Rules the verifier enforces:

- Node ids are non-negative integers, strictly increasing down the file, starting at `0`.
  Every operand (`a`, `b`, `c`) refers to an earlier node id (topological order).
- The number of `id = ...` lines **must not exceed** `NODES` (600). This is a hard size
  ceiling: a network that grows a giant lookup table or unrolls an enormous number of
  primitive gates will not fit beneath it. Keep the arithmetic clever and compact.
- Header lines (`VERSION`, `BITS`, `NODES`, `OUTPUT`) come before any node lines.
- `OUTPUT <node_id>` names the node whose 32-bit value is the function result `y`.
- The `NODES` value is your declared budget; node-line count must be `<= NODES`. You may
  declare `NODES 600` and use fewer lines.
- Node-line count is measured over `id = ` lines only (comments/header excluded).

Hints (you are of course free to implement the arithmetic any way you like; it must just
evaluate correctly inside the ceiling):

- `isqrt` is easy to build as a fixed number of iterations with `ULT` + `MUX`: keep a
  remainder `rem` (initialized to `x`) and a result; try a candidate `res + bit` where
  `bit` starts at `2^30` and shrinks by `>>2` each step; for `N`-bit inputs the algorithm
  needs an exact fixed number of steps (choose enough steps to reconstruct all 16 result
  bits; do not run extra steps past the stop condition). Beware 32-bit wraparound:
  `rem - (res+bit)` is only meaningful when the subtraction is actually taken, so guard it
  with `MUX(ULT(rem, res+bit), ...)`.
- Fibonacci to an *index that depends on the input* is expensive to unroll naively. Use
  **fast doubling**: from `(F_n, F_(n+1))` compute `F_(2n) = F_n*(2*F_(n+1)-F_n)`,
  `F_(2n+1) = F_n^2 + F_(n+1)^2` (all mod `2^32`). Walk the bits of `s` from the most
  significant bit down: at bit `b`, a `0` keeps the pair `(F_(2n), F_(2n+1))` and a `1`
  advances it to `(F_(2n+1), F_(2n+2))` with `F_(2n+2) = F_(2n) + F_(2n+1)`. Select the
  continuation with `MUX`, using `AND(SHR(s, k), 1)` to read each bit. 32 bit-steps × a
  handful of operations each fits comfortably under 600 lines.
- Reusing the same constant for many positions is free (create one `CONST` node and
  reference it everywhere).

### `/app/gate_validate.py`

Write a self-checking validator with this contract:

```
python3 /app/gate_validate.py <inputs_file>
```

- Loads `/app/gate_net.txt` and evaluates the network for every input in `<inputs_file>`.
- `<inputs_file>`: one unsigned 32-bit integer per line, decimal or `0x...` hex. Lines may
  contain blank lines and `#` comments (anything from `#` to end of line is ignored).
- For each input it compares the network output to the exact reference computed with
  Python's `math.isqrt` and a fast-doubling Fibonacci modulo `2^32`.
- Behavior: if every value matches, it prints a single line containing `PASS` and exits
  with status 0. Otherwise it prints `FAIL` and exits non-zero.

The grader runs this validator on hidden input files **and** evaluates `/app/gate_net.txt`
with its own independent interpreter over the same hidden inputs, so make sure
`/app/gate_net.txt` itself is correct — the validator is not allowed to paper over a wrong
network.

---

## Subtask 2 — Compressor under a strict size ceiling (`/app/compress.py`, `/app/payload.bin`)

Implement a compressor with built-in decompression for a literal/back-reference token
stream. You choose, for every span of the input, whether to emit it as **literal bytes** or
as a **back-reference**, and the grading is on the *total encoded size* of binary blobs.

### Token format (byte-exact; little-endian field order in a token)

- **Literal token**: `0x00` followed by exactly one byte of data — **2 bytes** total.
- **Back-reference token**: `0x01` followed by `len16` (2 bytes, LE, value `>= 2`),
  then `dist16` (2 bytes, LE, `1 <= dist16 <= 65535`) — **5 bytes** total.
  Decoding copies `len16` bytes from `dist16` bytes back into the already-decoded output
  (position `current_offset - dist16`), byte by byte. **Overlap is allowed**: one byte at a
  time, so `dist=1` with a large `len` expands a run (RLE), and `len > dist` is legal.
- The stream is consumed from start to end; there is no end-of-stream marker. Every token
  must decode within the output (a reference must not read before offset 0 — it can only
  copy bytes that are already in the output at the time it runs).

### `/app/compress.py` interface

```
python3 /app/compress.py <in_file> <out_file>          # compress
python3 /app/compress.py --decompress <in_file> <out_file>   # decompress
```

Compression must pick literal-vs-back-reference segments so that the encoded output is
small — the budget is a hard ceiling per input, and the all-literal encoding (2 bytes per
input byte via the literal token) always busts the budget the grader uses. A robust
strategy: locate the longest earlier match for each position within a 65535-byte window,
then run a dynamic program over positions minimizing total encoded bytes
(`dp[i] = min(2 + dp[i+1], 5 + dp[i+len])` when a match of `len` starts at `i`).

Edge cases the hidden blobs will probe (your code must handle all of them):

- **Long-distance references**: repetitions that occur hundreds to tens of thousands of
  bytes apart (but always within `dist16 <= 65535`).
- **Overlap / RLE runs**: long runs of a repeated byte (a `dist=1` reference), and repeats
  where `len > dist`.
- **Mostly-incompressible regions**: long stretches of bytes with no earlier match — they
  should degrade to literals; do not emit useless small back-references that cost 5 bytes
  to replace 2 bytes of literals.
- **Small / degenerate inputs**: inputs shorter than any useful match, and inputs where a
  byte equals later bytes such that matches could read past the remaining input (a match
  length can never exceed `remaining_input - start`).
- Empty input (0 bytes) is a valid input: it compresses to a 0-byte output that
  decompresses to 0 bytes.

Decompression must always reproduce the original input byte-for-byte; correctness beats
size (a wrong decode is an automatic fail even if the size is good).

### Deliverable: `/app/payload.bin`

`/app/sample.dat` (5596 bytes) is provided. Run your compressor on it and save the result
as `/app/payload.bin`. The verifier will:

1. Check `/app/payload.bin` decodes **exactly** to `/app/sample.dat`.
2. Check `size(/app/payload.bin) < 2800` bytes (the all-literal encoding of sample.dat is
   11192 bytes, so a compressor that never uses back-references cannot pass; the reference
   solution emits ≈2050 bytes — see guidance above for the DP approach).

The verifier will additionally run `/app/compress.py` on fresh hidden blobs (mounted at
verify time) of sizes from ~300 bytes to ~11 KB, including the edge structures above, and
check both the byte ceiling and that decompression equals the original.

---

## Subtask 3 — Bounded global environment footprint (`/app/footprint_report.txt`)

The container is shared with the grader: after you finish, the **global Python
site-packages directory** must not have grown beyond a bounded fraction of the pristine
baseline. This means: do **not** `pip install` heavy packages (scipy, torch, pandas,
matplotlib, scikit-learn, or anything of similar size) and clean up any large
intermediate artifacts you create. The `numpy` already installed is part of the baseline.

- The pristine baseline (bytes) is stored in `/opt/site-baseline.txt`.
- Site-packages is the directory returned by
  `python3 -c "import site; print(site.getsitepackages()[0])"`.
- **The size ceiling is** `limit = round(baseline * 1.08) + 12*1024*1024`. Everything that
  lives under site-packages counts (files in all subdirectories). A heavy install pushes
  the real size far past this limit; the grader re-measures the directory itself, so the
  report cannot fake a clean footprint.
- `pip` operates on caches in your calling user's home — clean those up too if you ran pip.

Write `/app/footprint_report.txt` in this exact key:value format (values are the decimal
byte counts, `true`/`false` literal at the end):

```
baseline_bytes: <int>
measured_bytes: <int>
limit_bytes: <int>
within_budget: true|false
```

- `baseline_bytes` is the integer read from `/opt/site-baseline.txt`.
- `measured_bytes` is what *you* measure right before finishing, with the same recursive
  sum over the entire site-packages tree (the grader re-measures and requires this number
  to equal its own measurement).
- `limit_bytes` is `round(baseline*1.08) + 12582912`.
- `within_budget` must be `true` — and must really be true, because the grader checks the
  measured size itself.

---

## Final checks before you finish

Make sure all of the following files exist and are correct:

```
/app/gate_net.txt        (VERSION 1 header; <= 600 node lines; OUTPUT node given)
/app/gate_validate.py    (prints PASS / exit 0 only when the net matches the reference)
/app/compress.py         (both modes; used by the grader on hidden blobs)
/app/payload.bin         (decodes to /app/sample.dat; size < 2800)
/app/footprint_report.txt (exact key:value format)
```

Debug locally: `python3 /app/gate_validate.py <your_test_inputs>`; test the compressor with
a few blobs, including one with a long run of one byte and one that repeats a chunk
thousands of bytes later; re-run your footprint measurement after any pip activity.
