# Basalt Fathom — manifest attestation chain

You are the integrity officer of an offline archive. Every artifact in
`/app/artifacts/` must carry an **attestation digest** derived by a fixed,
multi-step chain over the artifact's raw bytes. The chain mixes truncated
intermediate digests of different algorithms in a strict order — omitting a
truncation, reordering the concatenation, or swapping an algorithm changes the
result, so implement it exactly as specified.

## Deliverables (both required)

1. **`/app/solve.py`** — a general-purpose command-line program with these
   subcommands:
   ```
   python3 /app/solve.py attest <file>      # print the final attestation hex digest of <file>
   python3 /app/solve.py solve-evidence     # attest every file named in /app/artifacts/manifest.txt
                                            # and write /app/answer.json
   ```
   - `attest` prints exactly one lowercase hex string on its own line (a
     trailing newline is acceptable) and nothing else on stdout.
   - `solve-evidence` writes `/app/answer.json` (see below) computed by calling
     your own chain on each artifact listed in the manifest — do not hand-write
     the values.
   You may use only the Python 3 standard library. `python3` is available.

2. **`/app/answer.json`** — the attestation report for the shipped artifacts,
   produced by running `python3 /app/solve.py solve-evidence`.

## The attestation chain

Given the artifact's raw bytes `P`:

```
h1 = md5(P)                                  # raw digest, 16 bytes
h2 = sha512(h1[:8])                          # hash of the FIRST 8 BYTES of h1; raw digest, 64 bytes
h3 = blake2b(h2[:24] + h1[6:14],             # hash of the FIRST 24 BYTES of h2
             digest_size=20)                 #   CONCATENATED with BYTES 6..14 (slice [6:14]) of h1
final = sha3_256(h3 + P)                     # raw digest of the concatenation of h3 and the
                                             # ORIGINAL P; final is its lowercase hex form
```

In Python terms (the authoritative wording):

```python
h1 = hashlib.md5(P).digest()
h2 = hashlib.sha512(h1[:8]).digest()
h3 = hashlib.blake2b(h2[:24] + h1[6:14], digest_size=20).digest()
final = hashlib.sha3_256(h3 + P).hexdigest()
```

Every step matters: the truncations (`h1[:8]`, `h2[:24]`, `h1[6:14]`), the
concatenation order (`h2[:24]` **before** `h1[6:14]`, `h3` **before** `P`), and
the algorithms (`md5`, `sha512`, `blake2b` at 20 bytes, `sha3_256`) must be
exactly as written. The empty input (zero-length `P`) is valid and must work.

## `/app/answer.json`

Exactly this shape:

```json
{
  "attestations": {
    "blob.bin": "<64 lowercase hex chars>",
    "ledger.txt": "<64 lowercase hex chars>"
  },
  "artifact_count": 2
}
```

- `attestations` maps each artifact **filename** (as written in
  `/app/artifacts/manifest.txt`, one filename per line; blank lines ignored) to
  the attestation digest of that file's raw bytes.
- `artifact_count` is the number of attested files (int).

## Constraints

- Do not modify anything under `/app/artifacts/`. The verifier hashes the
  shipped artifacts and fails you if any byte changes.
- The verifier re-runs your program (`attest` subcommand) on hidden files —
  including an empty file, a file containing every byte value `0x00`..`0xFF`,
  and arbitrary binary blobs — and compares against an independent
  implementation of the chain above, so write a general tool, not a lookup
  table.
- No network access at verify time; standard library only.
