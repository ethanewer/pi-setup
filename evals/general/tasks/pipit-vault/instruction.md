# Recover the sealed vault passcode

A decommissioned key-storage service left its passcode shattered into
obfuscated shards inside `/app/vault`. Reassemble it with a reusable tool and
persist it **with the exact expected normalization** — the verifier compares
file contents byte-strictly.

Work in `/app`. Do **not** touch `/tests` or `/solution` (not visible to you).

## The vault layout (`/app/vault/`)

- `shards/` — a set of `shard-*.txt` files. Each **real** shard contains one
  line holding a **base32** token (RFC 4648, uppercase alphabet; accept
  lowercase tokens too). Files may contain leading/trailing whitespace or
  blank lines — strip before decoding. **Decoy** shards also live here: they
  decode fine but are NOT listed in the manifest and must be ignored.
- `manifest.json` — the assembly recipe:
  ```json
  {
    "order": ["shard-123a.txt", "shard-456b.txt", ...],
    "encoding": "base32",
    "reverse": true,
    "normalization": "lowercase-strip"
  }
  ```
  `order` lists, in assembly sequence, exactly the real shard filenames.
  Decoding each listed shard yields a byte chunk; concatenating the chunks in
  manifest order yields an obfuscated string. If `"reverse"` is `true`, the
  assembled string must be reversed.
- `checksum.txt` — one line: the lowercase hex SHA-256 of the **normalized**
  passcode (see below). It is the ground truth for your recovery.

## Normalization (this is what gets byte-checked)

The normalized passcode is the assembled (and, if requested, reversed) string
with:
- all surrounding whitespace removed, and
- **all letters lowercased**.

Example: an assembled+reversed string `KX7-Q9M2-Flare` normalizes to
`kx7-q9m2-flare`.

## Deliverables (both required)

1. `/app/recover.py` — a runnable Python tool with this interface:
   ```
   python3 /app/recover.py <vault_dir> <out_file>
   ```
   Behavior:
   - Read `manifest.json`, decode each listed shard (base32; strip whitespace,
     accept lowercase tokens), concatenate the byte chunks in order, reverse
     the result if `reverse` is `true`, and normalize (strip + lowercase).
   - **Verify** the result: SHA-256 of the normalized passcode must equal the
     hex digest in `checksum.txt`. On mismatch, print an error to stderr and
     **exit non-zero without writing the output file**.
   - On success write the normalized passcode to `<out_file>` followed by a
     **single trailing newline** and nothing else (no leading whitespace, no
     trailing spaces, exactly one final newline).
2. `/app/passcode.txt` — the output of running your tool on the provided
   vault:
   ```
   python3 /app/recover.py /app/vault /app/passcode.txt
   ```

## What the grader checks

- `/app/passcode.txt` contains exactly the normalized passcode (a file whose
  contents are `normalized + "\n"`, or exactly `normalized` — any trailing
  spaces, leading whitespace, or extra newlines fail).
- Your tool is re-run unchanged on **hidden vaults** with different secrets,
  different shard/decoy counts, and different `reverse` settings; each output
  is byte-checked the same strict way.
- A **corrupted hidden vault** (whose `checksum.txt` does not match the
  reassembled value) must make your tool exit non-zero and write nothing.
- Decoy shards must never leak into the result.

## Constraints

- Standard library only. No network access.
- Do not hard-code the visible secret, shard names, or shard count — the tool
  must work on any vault conforming to this layout.
- `/app/passcode.txt` must be produced by actually running `/app/recover.py`,
  not hand-edited.
