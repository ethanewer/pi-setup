# hazel-latch — Latchkey stream engine

Latchkey Systems runs an on-prem key-stream service. Ops ships an **external
launcher** at `/app/launcher.mjs` (a Node.js program — an immutable lab input,
do not modify it) whose only job is to **find, boot, and drive** your engine
binary. If the launcher cannot find the entrypoint exactly where it expects, or
the boot probe does not match, it prints `BOOT_FAIL` and the service never
comes up.

Your job: author the C source of the engine and build it into the native
binary the launcher expects, so the launcher reports `SESSION_OK` on every
session it is given — including hidden ones it holds in reserve.

## Deliverables (both required)

1. `/app/bin/latch-engine` — a native ELF executable (not a script), built
   from your source, e.g.:
   ```
   gcc -O2 -o /app/bin/latch-engine /app/src/latch_engine.c
   ```
2. `/app/src/latch_engine.c` — the C source. The verifier **recompiles it from
   scratch** with `gcc -O2` and requires the rebuilt binary to behave
   identically (probe, sessions, everything), so the source must be the real
   implementation.

## The launcher's boot contract (read `/app/launcher.mjs` — it is the spec)

Running `node /app/launcher.mjs <session-file>` the launcher:

1. **Discovery** — requires an executable at exactly `/app/bin/latch-engine`.
   Anything else (missing file, wrong path, not executable) → `BOOT_FAIL`.
2. **Boot probe** — runs `/app/bin/latch-engine --probe` and requires exit
   status 0 with stdout **exactly** `LATCH/1 READY\n` (nothing else).
3. **Session** — parses the session file (first non-comment line is
   `seed=<int 0..4294967295>`; `#` lines and blank lines are skipped;
   remaining lines are decimal request counts `n`, `0 <= n <= 1000000`), then
   spawns `/app/bin/latch-engine --serve <seed>`, writes each request count as
   one stdin line, closes stdin, and compares the engine's stdout **frame by
   frame** against its own independent reference (keystream + CRC-32). It
   prints `FRAME_OK <i>` per request and finally `SESSION_OK <count>` with
   exit 0 only if every frame and CRC matches byte-for-byte and there is no
   trailing output.

## Engine contract

### `latch-engine --probe`
Print exactly `LATCH/1 READY` and a newline to stdout; exit 0.

### `latch-engine --serve <seed>`
- `<seed>` is a decimal integer in `0..4294967295`. Initialize the 32-bit
  unsigned state `s = seed`. Any other usage (missing/wrong arguments, seed
  out of range or non-numeric) → brief message to **stderr**, exit **2**,
  nothing on stdout.
- Read stdin line by line until EOF. Skip empty (whitespace-only) lines. Each
  other line must be a decimal request count `n` (`0..1000000`); a malformed
  line → brief message to stderr, exit 2.
- For each request, emit exactly one frame on stdout:
  ```
  BEGIN <n>
  <payload>
  END <crc8hex>
  ```
  - `<payload>` is the next `n` letters of the **shared keystream**, on one
    line. The keystream is advanced per letter: `s = (s * 1664525 + 1013904223)
    mod 2^32` (unsigned 32-bit wraparound), then the letter is
    `chr(97 + (floor(s / 128) mod 26))` — i.e. take bits `7..31` of the new
    state, mod 26, offset by `'a'`. The state **persists across requests**
    within the session (it is a single continuous stream).
  - `<crc8hex>` is the CRC-32 (IEEE 802.3: reflected polynomial `0xEDB88320`,
    initial value `0xFFFFFFFF`, final XOR `0xFFFFFFFF` — the standard
    zlib/PNG CRC-32) of the payload's bytes, printed as exactly **8 lowercase
    hex digits** (e.g. `00000000` for the empty payload).
- `n = 0` is legal: the frame is `BEGIN 0`, an empty payload line, and
  `END 00000000`.
- On stdin EOF: exit 0. Emit **nothing** on stdout except the frames (and the
  banner in probe mode).

### Sanity check

With the shipped sample session:

```
node /app/launcher.mjs /app/samples/session.txt
```

must print `FRAME_OK 0`, `FRAME_OK 1`, `FRAME_OK 2`, `SESSION_OK 3` and exit 0
(the session has seed 42 and requests 5, 0, 12).

## Constraints

- `gcc` and `node` are preinstalled; no network access at verify time; C
  standard library only.
- Do not modify `/app/launcher.mjs` or `/app/samples/session.txt`.
- The verifier runs your binary unchanged on **hidden session files** with
  other seeds (including `0` and `4294967295`) and request counts (including
  `0` and long runs) — the keystream, CRC, framing, probe banner, and
  argument-order (`--serve <seed>`) must all match exactly. Do not hard-code
  to the sample session.
