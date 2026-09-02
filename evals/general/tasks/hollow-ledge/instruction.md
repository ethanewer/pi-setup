# Hollow Ledge vault recovery

You are a recovery engineer called in after a cipher-heighten breach of the
"Ledge" on-prem ledger. The database `ledge.db` survives, but its write-ahead
log was obfuscated with a single-byte cipher, and the vault's private material
was "deleted" and repacked inside a stale log thumbnail. You must recover the
artifacts, then record the credentials. Everything below is exact:

- All paths, output formats, filenames and edge cases are authoritative.
- **Do not modify** `/app/src/check.c`, `/app/carrier.bin`, `/app/ledge.db` or
  `/app/ledge.db-wal.obf`.
- **Never read `/tests`** — it is not part of your workspace and is hidden.

## Deliverables (create all of these)

| Path | Meaning |
|------|---------|
| `/app/decode.c` | your recovery program, compiled with `gcc -O2 -o /app/decode /app/decode.c`; must implement the two subcommands below and be runnable **on arbitrary new inputs** |
| `/app/creds.txt` | the recovered user + valid password (Part 5) |
| `/app/key.pem` | the recovered private key immediately followed by the certificate (Part 4) |
| `/app/recovered/privkey.pem`, `/app/recovered/cert.pem` | byte-exact carved blobs (Part 2) |
| `/app/ledge.db-wal` | the restored, **valid** WAL (Part 1) |

The evaluation re-runs your `/app/decode.c` on **hidden** WAL and carrier files
(not the ones in `/app`), so `/app/decode.c` must be a general, reusable tool,
not a hard-coded one-off for these exact bytes.

---

## Part 1 — recover the valid WAL (reverse the single-byte byte transform)

`/app/ledge.db-wal.obf` is a real SQLite WAL file whose every byte has been
XOR'd with a single one-byte key `k`: `obf_byte = wal_byte ^ k`. You must find
`k` and invert the transform to produce the valid WAL.

- The native SQLite WAL header begins with the magic bytes `37 7f 06 82`
  (the first four bytes of every valid WAL). That gives you an unambiguous way
  to identify `k`: it is the byte that, XORed into the obfuscated header, yields
  `37 7f 06 82`. There is exactly one such byte.
- Write the decoded bytes to **`/app/ledge.db-wal`** (valid WAL, correct magic).
- Once `ledge.db-wal` is in place, read the `cfg` table (e.g. with Python's
  `sqlite3` module) to recover: `username`, `salt`, `passhash`, `endpoint`.
  These rows were committed-but-never-checkpointed, so they exist **only** after
  the valid WAL is restored.

`/app/decode.c` must provide this subcommand (as an executable named `/app/decode`):

```
/app/decode unwal <obf_wal_path> <out_wal_path>
```

It finds the single byte key via the WAL magic, XOR-decodes the whole file, and
writes the valid WAL to `<out_wal_path>`. It must work for **any** obfuscated
WAL (any key byte, any length). Print a line `KEY=<k>` (decimal) to stdout.

## Part 2 — carve the deleted/embedded private key + certificate

`/app/carrier.bin` is mostly padding bytes, but it embeds the deleted vault
private key and its certificate as two **length-prefixed** PEM blobs:

```
LVPR  <u32 LE length>  <private-key PEM bytes>
LVCR  <u32 LE length>  <certificate PEM bytes>
```

- Search the carrier for the `LVPR` marker, read the little-endian `u32`
  length, and take exactly that many bytes as the private key PEM.
- Then find `LVCR`, read its length, and take that many bytes as the certificate.
- Write the two PEM blobs byte-for-byte (exact bytes, no modification) into the
  clean directory `/app/recovered/` as `privkey.pem` and `cert.pem`.
- `/app/recovered/` must contain **nothing else** (no original carrier, no temp
  files — just those two files).

`/app/decode.c` must provide this subcommand:

```
/app/decode carve <carrier_path> <outdir>
```

It scans `<carrier_path>`, recovers the two length-prefixed blobs, and writes
`<outdir>/privkey.pem` and `<outdir>/cert.pem` (creating `<outdir>` if needed).
It must work for **any** carrier (different offset, different key/cert, any
lengths).

## Part 3 — reverse the password check to a valid secret

The vault validates an operator password against `/app/src/check.c` (and the
pre-built `/usr/local/bin/ledgecheck`, built from that exact source). Read the
routine and invert it:

- A valid secret is a printable ASCII string of **exactly 12 bytes**, `S[0..11]`
  (bytes each in `0x20`–`0x7e`), such that running each byte through
  `f(x) = ( (x * 0x35 + 0x2f) ^ 0xa5 ) & 0xff` reproduces the stored fingerprint
  `FP` that you read from the `cfg` table (`passhash`). `f` is a bijection on the
  256 byte values, so inversion is a lookup: `x = ( ((y ^ 0xa5) - 0x2f) * inv35 ) & 0xff`
  with `inv35` the mod-256 inverse of `0x35` (`inv35 = 109`).
- The recovered **valid secret** is the fingerprint run through that inverse.
- Cross-check: `/usr/local/bin/ledgecheck "<your secret>"` must print `ACCEPT`.

## Part 4 — combined key-and-certificate PEM

Build `/app/key.pem` as the **byte concatenation** of the recovered private key
followed immediately by the recovered certificate — that is, the exact bytes of
`/app/recovered/privkey.pem` then the exact bytes of `/app/recovered/cert.pem`,
with no separator, in that order.

## Part 5 — record the recovered credentials

Write `/app/creds.txt` with exactly these two lines (in this order):

```
username=<username from the restored cfg table>
password=<valid secret from Part 3>
```

No trailing extra lines, no header. `<username>` must be exactly the `username`
value recovered from the restored `cfg` table.

## Hidden evaluation

The verifier compiles `/app/decode.c` itself and runs:
- `unwal` on a **hidden** obfuscated WAL (a different key byte and different
  content) and checks the output is a valid SQLite WAL (correct magic, sane
  header).
- `carve` on a **hidden** carrier embedding a different key/cert pair and byte-
  compares the two recovered blobs against the reference. To pass, `/app/decode.c`
  must be generic, not tailored to these guessed bytes.

If all deliverables are correct and every check passes, the reward is 1.