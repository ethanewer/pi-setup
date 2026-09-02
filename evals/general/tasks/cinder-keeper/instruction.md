# Cinder firmware keeper — buffer/gate payload

The **Cinder** appliance ships a small firmware gate program. You must study
its source and craft an exact byte-level input that overruns the fixed tag
buffer so the neighbouring `permit` control word is set to the magic value
that opens the gate, and produce a reusable payload crafter that generalizes
to other gate builds.

## Environment

- Working directory: `/app`. It already contains `/app/keeper.c` — the gate
  source. Read it. `gcc` and `python3` are installed. No network.
- **Do not modify `/app/keeper.c`.**
- Build for testing: `gcc -O0 -o /tmp/keeper /app/keeper.c`, then run
  `/tmp/keeper < payload.bin`.

## How the gate works (read the source; these facts are exact)

- `struct session` holds `char tag[TAG_LEN];` immediately followed by
  `unsigned int permit;` — with the fixed `TAG_LEN` there is **no padding**
  between them (little-endian x86-64, `gcc -O0`).
- `main` reads up to `TAG_LEN + sizeof(unsigned int)` bytes from stdin
  directly into the struct starting at `tag`, so the last **4 bytes** of the
  input land on `permit`.
- The gate opens only when `permit == PERMIT_MAGIC` (interpreted as a native
  little-endian 32-bit unsigned integer). Open gates print
  `KEEPER_OPEN code=<CODE>`; otherwise the program prints `LOCKED`.
- The source pins both constants:
  - `#define TAG_LEN <n>` — decimal integer
  - `#define PERMIT_MAGIC <0xhex | decimal>` — optionally suffixed with `u`,
    `l`, or both, in upper- or lower-case hex

## The payload contract (exact)

A conforming payload for a gate source is **exactly `TAG_LEN + 4` bytes**:

```
< TAG_LEN filler bytes > < 4-byte little-endian unsigned int PERMIT_MAGIC >
```

The filler bytes are arbitrary; anything except the exact length or the exact
little-endian magic keeps the gate locked. An underrun (fewer bytes), an
overrun, a big-endian encoding, or a wrong value all print `LOCKED`.

## Deliverables (both required)

1. `/app/craft.py` — a reusable payload crafter with this interface:

   ```
   python3 /app/craft.py <keeper_source.c> <output_payload>
   ```

   It must parse `TAG_LEN` and `PERMIT_MAGIC` out of the given C source (via
   their `#define` lines, accepting decimal or `0x…` hex with optional
   `u`/`l` suffixes — never assume the visible values), build the payload per
   the contract above, write it to `<output_payload>`, and exit `0`. On a
   source lacking either define it must exit non-zero without writing the
   output.

2. `/app/exploit.bin` — the payload for the **visible** `/app/keeper.c`
   (produce it by running your crafter on the provided source), such that:

   ```
   gcc -O0 -o /tmp/keeper /app/keeper.c && /tmp/keeper < /app/exploit.bin
   ```

   prints `KEEPER_OPEN code=KX-3317`.

## Edge cases the grader probes with hidden fixtures

- The verifier compiles **fresh gate sources** under `/tmp` with different
  `TAG_LEN` values and different `PERMIT_MAGIC` values (decimal and hex
  spellings, with and without `u` suffixes), runs your `/app/craft.py`
  unchanged against each, and feeds the crafted payload to the compiled
  binary. Your crafter must derive everything from the source text.
- Each hidden gate expects its own unlock code; the verifier checks the
  `KEEPER_OPEN code=<CODE>` line matches that build's constant from its
  source.
- `PERMIT_MAGIC` values include cases with leading zero bytes (e.g. high
  byte `0x00`) — the payload must still be exactly `TAG_LEN + 4` bytes and
  must not be truncated at a NUL.

## Constraints

- Work in `/app`. Do not modify `/app/keeper.c`.
- No network access; use only `gcc`, `python3`, and the standard library.
- The verifier re-runs your crafter on every fixture; a hand-written
  fixed-byte payload without a working general crafter fails the hidden
  cases.
