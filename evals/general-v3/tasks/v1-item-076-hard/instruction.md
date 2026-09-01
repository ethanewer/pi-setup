# Reverse-engineer a bit-packed custom compression format (hard)

A pair of compiled command-line tools implements an unusual **bit-packed** compression scheme.
Your job is to reverse-engineer the exact on-disk format **from their observable behavior**, then
implement (a) a decoder byte-identical to the oracle and (b) an encoder that produces streams the
oracle decodes correctly. This is a hard, adversarial task: the stream header and token fields are
**not byte-aligned** — they are packed into a bitstream, so you must recover exact bit widths,
bit order, and offsets.

## What is available in the container

- `/app/decompress` — the **oracle decoder** (compiled C binary). Usage:
  `/app/decompress <compressed_path>` writes decoded bytes to **stdout** (raw binary, `argv[1]`).
  No source is available; start by feeding it crafted inputs.
- `/app/enc` — compiled C encoder. Usage: `/app/enc <plaintext> <out.bin>` gives you a compressed
  stream for round-trip inspection.
- `/app/corpus/` — matching `c1.txt`…`c5.txt` and `c1.bin`…`c5.bin`. Use these exact pairs to
  infer how bits are laid out. The pairs span all token kinds (pure-literal, short-run
  back-references, and long-range back-references).

## Deliverables

Create two files:

1. **`/app/solve/decode.py`** — Python 3, identical interface to the medium task requirements:
   - reads `argv[1]` as a binary compressed stream,
   - writes the decompressed **bytes** to `sys.stdout.buffer` (binary) only,
   - handles arbitrary bytes `0x00`–`0xFF`, overlapping back-references, and never corrupts binary
     output via text-mode I/O.

2. **`/app/solve/encode.py`** — Python 3, the reverse direction:
   - reads a plaintext file (`argv[1]`), writes a **valid compressed stream** to
     `sys.stdout.buffer` that the oracle `/app/decompress` will decode back to the exact original.

## Requirements / emphasis

- **Completeness.** Your `decode.py` must handle every valid stream the oracle accepts: literals,
  short and long back-references, any offset/length combination the format encodes, and streams
  with any byte values.
- **Round-trip verification.** For many inputs you try, prove consistency three ways:
  - `decode(encode(x)) == x` (your own pair)
  - your `decode.py` output matches the oracle `decompress` on the same stream
  - your `encode.py` output is decodable by the oracle (i.e., you have not invented your own format)
- **Adversarial edges.** Hidden grading streams are designed to break simple guesses: overlapping
  copies, max-length repeated runs, pure-literal streams, and streams with no trailing
  alignment marker.

## Ground truth

For anything compressed, `/app/decompress` is the reference. Your decoder must agree with it on
**every byte** for every hidden stream. Partial agreement is scored proportionally, but aim for
exact byte equality on the hidden set. Do not print anything besides binary output from either
program.