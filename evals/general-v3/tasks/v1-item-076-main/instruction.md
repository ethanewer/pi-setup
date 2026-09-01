# Reverse-engineer a custom compression format and implement a compatible decoder

A transport format is used by two compiled command-line tools in this container. Your job is to
reverse-engineer the format **from their observable behavior** and implement a decoder that
reproduces the exact decompressed bytes for any valid compressed stream.

## What is present in the environment

- `/app/decompress` — the **oracle decoder** (a compiled C binary). Given a compressed stream it
  produces the original file.
  - Usage: `/app/decompress <compressed_file> <returned on stdout>` — pass the stream path as
    `argv[1]`; it writes the decoded bytes to **stdout exactly** (no decorations).
  - No source code is available; you must infer the byte layout by probing it.
- `/app/enc` — an **encoder** (compiled C binary). Given a plaintext file it produces the
  corresponding compressed stream.
  - Usage: `/app/enc <plaintext_file> <output_compressed_file>`.
  - Use it to **round-trip**: pick your own plaintext, compress it with `/app/enc`, then... you
    can inspect the bytes and confirm what your decoder recovers.
- `/app/corpus/` — a public corpus of matching pairs to help you reverse-engineer:
  - `c1.txt`…`c5.txt` : plaintext files
  - `c1.bin`…`c5.bin` : the compressed stream produced from each `.txt` counterpart
  - These give you known *plaintext-pair* to dissect the format.

## Deliverable

Create **`/app/solve/decode.py`** — a self-contained Python 3 program that:

1. Reads a compressed stream **very directly** from the file given by `sys.argv[1]`.
2. Decompresses it to the **bytes** of the original file.
3. Writes those bytes to **stdout using binary mode**.

Constraints:

- The format is **binary**. Any byte `0x00`–`0xFF` may legitimately appear anywhere in the output
  (including inside a "text" file). You MUST do all I/O in binary:
  - open the input with `open(path, 'rb')`
  - write output with `sys.stdout.buffer.write(...)`
  - never decode the input to text or let the interpreter normalize line endings.
- Your decoder must accept **any** valid stream the encoder produces — not just the corpus files.
- Support **overlapping** back-references: when a token copies a run from earlier output, the copy
  may overlap its own destination (byte-by-byte copies, like LZ77), even when the run is longer
  than the current-output offset.
- Do not print anything else (no progress, no warnings, no trailing bytes) to stdout.

## How work with the oracle

Use `/app/decompress` as ground truth. For any compressed file `X`, the bytes it prints are the
exact bytes your `decode.py` must produce. Construct small probe streams, run both, and compare
them byte-for-byte to confirm your understanding and your implementation.

## Acceptance

When graded, the harness will run `python3 /app/solve/decode.py <stream>` for hidden compressed
streams and compare, byte-for-byte, against what `/app/decompress` produces. `decode.py` must
exist and run, output only binary bytes, and match the oracle. Aim for **all** hidden streams.