# Zephyr toolchain bring-up

You are standing up the **Zephyr** compression toolchain from source, inside
this one container, and you must prove it works end-to-end. The toolchain
ships a small compiler (the **Zephyr C-like compiler**, `zep`), a bundled
**decoder** for the "drift" stream format, a runtime header, and a fixed
corpus.

Your job has four dependent parts:

1. **Build the compiler from its source tree** and put a working `cc` at
   `/app/cc/bin/cc`.
2. **Compile the provided decoder** with that built compiler.
3. **Author a drift encoder** that, via the decoder, round-trips any payload
   byte-for-byte, and produce the compressed artifact plus a verification
   file.
4. **Gate the runtime header** behind a strict C++11 compile flag.

You are graded on the deliverables. Do all work under `/app`.

## What is already in the image (under `/app`)

| Path | Purpose |
|------|---------|
| `/app/src/zephyr/` | Source tree of the **Zephyr** compiler (`zep.c`, `Makefile`, `README.md`). You build it. |
| `/app/deck/drift.zh` | The provided **decoder** in the Zephyr language. Read it: it *is* the drift format spec. Do not modify. |
| `/app/deck/cardinal.h` | Runtime header consumed by the probe (strict C++11). Do not modify. |
| `/app/data/reference.txt` | The fixed corpus you must round-trip. Do not modify. |
| `/app/probe/probe.cpp` | The probe TU (declaratively-empty consumer of `cardinal.h`). Do not modify. |

`README.md` under `/app/src/zephyr/` fully documents the Zephyr language and
the compiler's command-line interface.

## 1 — Build the compiler (deliverable `/app/cc/bin/cc`)

```bash
cd /app/src/zephyr
make
make install
```

`make install` places the driver under `/app/cc/bin` and names it `cc`. Verify it
works:

```bash
printf 'int main(){ out(65); return 0; }\n' > /tmp/smoke.zh
/app/cc/bin/cc -o /tmp/smoke /tmp/smoke.zh && /tmp/smoke
```

The deliverable `cc` must be a real, working compiler: it must be able to
compile a brand-new `.zh` program to a runnable executable, and (with `-c`)
to a relocatable object, from a pristine context.

## 2 — Compile the decoder with the built compiler (produce `/app/unpack`)

Read `/app/deck/drift.zh` carefully — it is the authoritative decoder spec.
Then compile it **with the compiler you just built**:

```bash
/app/cc/bin/cc -o /app/unpack /app/deck/drift.zh
```

`/app/unpack` reads a **drift stream on stdin** and writes the decoded payload
on **stdout**; it exits `0` on success. Your encoder must always produce a
stream that decodes cleanly.

## 3 — Author the drift encoder (produce `/app/pack`, `/app/drifted.bin`, `/app/verify.txt`)

### The drift frame format (what `drift.zh` implements)

A stream is a sequence of frames, each starting with one control byte `h`:

* **High bit clear** `(h & 0x80) == 0` — **literal frame**: let
  `n = (h & 0x7F) + 1`, i.e. `1..128`; the **next `n` bytes** are copied
  verbatim to the output.
* **High bit set** `(h & 0x80) != 0` — **RLE frame**: let
  `rep = (h & 0x7F) + 1`, i.e. `1..128`; the **single byte that follows** is
  emitted `rep` times.

A payload is reproduced byte-for-byte exactly when the frames concatenate to
precisely that payload. There is **no length prefix**, so one stray frame
corrupts everything after it.

### Deliverables for this part

- **`/app/pack`** — an executable you author, in Zephyr, compiled with your
  `cc`, that reads **any payload on stdin** and writes a valid drift stream on
  **stdout**. It will be run against payloads you have never seen, so it must
  be a general correct encoder, not a special case. It must handle raw bytes
  (including `NUL`, `0xFF`, and every other byte value) reliably.
- **`/app/drifted.bin`** — the drift stream `/app/pack` produces for the corpus.
- **`/app/verify.txt`** — one line, exact format:
  `ROUNDTRIP_OK <sha256hex>` where `<sha256hex>` is the **SHA-256 of the
  recovered bytes** (i.e. of `/app/data/reference.txt`), and nothing else.
- **`/app/recovered.bin`** — `decode(drifted.bin)` (not graded; useful to debug).

Your encoder must be a real compressor: for the corpus it must emit a stream
**smaller than the input** (a correct RLE+literal encoder achieves this; a
pure-literal encoder does not).

### Round-trip procedure

```bash
/app/pack    < /app/data/reference.txt > /app/drifted.bin
/app/unpack  < /app/drifted.bin         > /app/recovered.bin
cmp /app/recovered.bin /app/data/reference.txt        # must match
sha=$(sha256sum /app/recovered.bin | awk '{print $1}')
printf 'ROUNDTRIP_OK %s\n' "$sha" > /app/verify.txt
```

The grader will exercise payloads containing **NUL and `0xFF` bytes**;
**very long runs** (longer than 128, so a run must be split across multiple
RLE frames); an **exact 128-byte literal region**; the **end-of-input**
boundary (keep reading literal data, but never read past the end of the
payload, and never emit a frame that would decode to more bytes than the
input); and **high-entropy / mixed text**. Validate by checking
`decode(encode(x)) == x` over many payloads: random bytes, all-`0`, all-`A`,
repeats, and text.

## 4 — Strict C++11 probe (produce `/app/probe.o`)

`/app/probe/probe.cpp` includes `cardinal.h` and must compile as strict
C++11. Compile it with the image's C++ compiler:

```bash
g++ -std=c++11 -pedantic-errors -I/app/deck -c /app/probe/probe.cpp -o /app/probe.o
```

A clean compile proves the header is compatible with the advertised standard.

## Constraints

- Do **not** modify `/app/deck/drift.zh`, `/app/deck/cardinal.h`,
  `/app/probe/probe.cpp`, or `/app/data/reference.txt`, and never hard-code an
  answer: every deliverable must come from real work you perform here.
- Deliverables live **exactly** at the listed paths and must remain runnable
  after your session ends.
- `/app/pack` and `/app/unpack` take no arguments and no interactivity; they
  stream raw bytes on stdin and stdout.

## Required deliverables

- `/app/cc/bin/cc` — built Zephyr compiler, working.
- `/app/unpack` — decoder compiled with the built compiler.
- `/app/pack` — your general encoder, runnable.
- `/app/drifted.bin` — compressed corpus.
- `/app/probe.o` — strict-C++11 object.
- `/app/verify.txt` — the `ROUNDTRIP_OK <sha256>` line.