# Blue Comet — compact block codec

You must design and implement a small binary **block codec** as a reusable Python
program. The encoding is your own implementation of the "Blue Comet" format,
specified completely below and in `/app/FORMAT.md`.

## Deliverable

Write exactly one module:

```
/app/codec.py
```

It must expose two functions:

```python
def encode(infile: str, outfile: str) -> None: ...
def decode(infile: str, outfile: str) -> None: ...
```

- `infile` / `outfile` are **file paths** (absolute or relative). All I/O is **binary**
  (open files in `"rb"` / `"wb"` mode).
- `decode` must raise an exception on any invalid stream (see Edge cases) and must
  **never** write an output for an invalid stream, and must never produce more bytes
  than a block's declared size.
- The module must be importable (not depend on `if __name__ == "__main__"`), and it
  must work for *any* input file content — arbitrary bytes, any length.

Your codec will be executed by an independent verifier against cases you do not see,
so it cannot hard-code any specific data. Do not read `/tests`, `/solution`, or any
input more than once.

## The format

Exactly as documented in `/app/FORMAT.md`. Summary:

- **Stream** = concatenation of independent blocks.
- Block header (7 bytes): magic `"BC7!"`, `planned_len` as uint16 **big-endian**
  (0..65535), then one `block_type` byte: `0x00` = literal, `0x01` = RLE.
- **literal**: the next `planned_len` raw bytes.
- **RLE**: a sequence of `(run_len u8, byte u8)` pairs whose `run_len` values sum to
  exactly `planned_len`; each `run_len` in 1..255.
- Inputs longer than 65535 bytes must be split into multiple blocks (max 65535
  bytes per block), concatenated in order.

## Edge cases the hidden verifier probes (implement and document these)

Invalid/malformed — `decode` MUST raise and emit nothing:
1. Fewer than 7 bytes remaining for a header (truncated header or headerless tail).
2. Wrong magic (anything other than `BC7!`).
3. `block_type` other than `0x00`/`0x01`.
4. literal block with fewer than `planned_len` payload bytes.
5. RLE block whose stream ends before the pairs fill `planned_len`.
6. RLE block where a pair's `run_len` would push the count past `planned_len`.
7. RLE pair with `run_len == 0`.

Valid but easy to get wrong (must round-trip cleanly):
- A completely empty stream (zero blocks) → empty output both directions.
- `planned_len == 0` literal block (valid).
- Max single block `planned_len == 65535`.
- A run exactly `255` long, and a run exactly filling the block.
- Input larger than one block → several concatenated blocks.
- Arbitrary binary data (including every byte value and `0x00` bytes) and no
  newline assumptions.

## What you must NOT do
- Do not modify, delete, or rename your input files, including `/app/sample.txt`
  and any file from `/app`. Read them only.
- Do not import or read from `tests/` or `solution/`.
- Do not make network calls.

## Visible example
Use `/app/sample.txt` as your smoke test: `decode(encode(sample.txt))` must equal
`sample.txt` byte-for-byte. The verifier independently checks this example plus its
own hidden round-trips and malformed-stream rejection.

When finished, ensure `/app/codec.py` is present and importable. There is nothing to
print; correctness is decided by the verifier running your program.