# Amber Braid gateway — mint the TLS bundle

You are the platform engineer provisioning TLS for the **Amber Braid**
delivery gateway. The gateway's loader refuses any certificate material that
is not shipped as a **single combined PEM bundle** (private key block first,
certificate block second) plus a fingerprint manifest. Everything is driven
from a small key=value specification file.

## Environment

- Working directory `/app`. The visible spec is `/app/provision/spec.env`
  (read-only — do **not** modify it). The `openssl` CLI and Python 3.12 are
  available; there is **no network**.
- Spec format: one `key=value` pair per line; blank lines and lines starting
  with `#` are ignored. Keys:
  - `key_type` — `RSA` or `EC`
  - `key_bits` — RSA modulus size (only present when `key_type=RSA`)
  - `curve` — EC curve name such as `prime256v1`, `secp384r1`, `secp521r1`
    (only present when `key_type=EC`)
  - `common_name`, `organization`, `country` — X.509 subject components
    (country is the two-letter code)
  - `validity_days` — certificate validity in days

## Deliverables (all required)

1. `/app/mkbundle.py` — a runnable Python program with this interface:
   ```
   python3 /app/mkbundle.py <spec_file> <bundle_out> <manifest_out>
   ```
   It reads the spec, mints a **fresh** key + matching self-signed
   certificate, and writes:
   - `<bundle_out>` — one PEM file containing **exactly two blocks in this
     order**: the private-key block
     (`-----BEGIN PRIVATE KEY-----` ... `-----END PRIVATE KEY-----`) first,
     then the certificate block
     (`-----BEGIN CERTIFICATE-----` ... `-----END CERTIFICATE-----`).
     Standard PEM headers/footers, base64 bodies. The file mode must be
     `0600`.
   - `<manifest_out>` — exactly two lines:
     ```
     cert_fingerprint_sha256=<64 lowercase hex>
     pubkey_fingerprint_sha256=<64 lowercase hex>
     ```
     where `cert_fingerprint_sha256` is the SHA-256 of the certificate's DER
     encoding and `pubkey_fingerprint_sha256` is the SHA-256 of the DER
     encoding of the key's `SubjectPublicKeyInfo` (i.e. the output of
     `openssl pkey -pubout -outform DER`). No colons, no trailing spaces.
   The certificate must satisfy the spec exactly: subject components, key
   type/size or curve, and a validity period of `validity_days` days (a
   ±1-day slack is tolerated for notBefore/notAfter rounding). The
   certificate's public key must equal the private key's public key. The
   program must work on **any** spec following the format — not just the
   provided one — and must not depend on network access or pre-existing key
   material.

2. `/app/bundle.pem` — the bundle your program produces for the **provided**
   spec:
   ```
   python3 /app/mkbundle.py /app/provision/spec.env /app/bundle.pem /app/manifest.txt
   ```

3. `/app/manifest.txt` — the manifest produced by that same run.

## What the grader does

It runs `python3 /app/mkbundle.py` on **hidden spec files you have never
seen** (different key types — RSA and EC with different curves/bits —
different subjects, different validity periods, comments and blank lines in
the spec) and validates, for each produced bundle:

- the file parses as PEM and contains a private-key block **before** the
  certificate block;
- the file mode is `0600`;
- the certificate's public key matches the private key's public key;
- the subject components, key type, key size / curve, and validity span match
  the hidden spec;
- the manifest fingerprints match recomputation from the bundle.

It also validates `/app/bundle.pem` and `/app/manifest.txt` against the
provided `/app/provision/spec.env` the same way. A bundle with a missing,
duplicated, reordered, or unparseable PEM block fails.

## Constraints

- Work only inside the container; do not modify `/app/provision/spec.env`.
- Standard library plus the `openssl` CLI; no network at build or verify time.
- `/tests` and `/solution` are not available to you.
- Keep `/app/mkbundle.py` robust: every openssl invocation must succeed and
  every parse must be guarded; a spec with extra whitespace or comments must
  still work.
