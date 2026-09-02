# Garnet Drift — provision a combined key-and-certificate PEM bundle

You are the platform engineer onboarding the **Garnet Drift** edge fleet to a
legacy load balancer. The balancer's older firmware cannot load a key and a
certificate from separate files: it accepts exactly **one combined PEM file**
containing the private-key block followed by the certificate block. Your job
is to build the reusable bundling tool and to provision the edge service with
a correct combined bundle.

## Provided inputs (read-only — do **not** modify them)

- `/app/pki/edge.key` — the private key of the edge service (PKCS#8,
  `BEGIN PRIVATE KEY`).
- `/app/pki/edge.crt` — the edge service's self-signed certificate.
- `/app/pki/retired.key` — a **retired** key from the decommissioned fleet.
  It does **not** match `edge.crt` and must never end up in the bundle.
- `/app/pki/retired.crt` — the retired certificate (for reference).
- `/app/pki/edge.csr` — the original signing request (for reference).

The `openssl` CLI is installed. Python 3.12 is available as `python3`.

## Deliverables (all required)

### 1) `/app/mkbundle.py` — the reusable bundling tool

```
python3 /app/mkbundle.py <key_file> <cert_file> <output_file>
```

It must:

- Read `<key_file>` and extract the **first private-key PEM block** (any of
  the headers `PRIVATE KEY`, `RSA PRIVATE KEY`, `EC PRIVATE KEY`,
  `ENCRYPTED PRIVATE KEY`). Input files may contain leading/trailing
  non-PEM text, blank lines or comments — skip anything that is not part of
  a PEM block.
- Read `<cert_file>` and extract the first `CERTIFICATE` PEM block.
- **Verify that the key matches the certificate** (their public keys are
  equal). You may shell out to the `openssl` CLI to compare public keys.
- If the key does **not** match the certificate, print a diagnostic to
  stderr, exit with a **non-zero status**, and **not** create the output
  file.
- Otherwise write `<output_file>` containing exactly two PEM blocks in this
  order: the private-key block first, then the certificate block, separated
  by a single newline, with a trailing newline at the end of the file. Blocks
  keep their standard `-----BEGIN ...-----` / `-----END ...-----` armour and
  their base64 payload (whitespace-normalised to single `\n` line breaks).
- Set the output file's permissions to **`0600`**.
- Never modify the input files; never crash on malformed input — exit
  non-zero with a diagnostic instead.

The tool must work on key material you have never seen, including PKCS#8
RSA (`BEGIN PRIVATE KEY`), traditional RSA (`BEGIN RSA PRIVATE KEY`) and SEC1
EC (`BEGIN EC PRIVATE KEY`) keys.

### 2) `/app/pki/bundle.pem` — the provisioned combined bundle for the edge service

Produce it by **running your tool** on the correct pair for `edge.crt`:

```
python3 /app/mkbundle.py <the matching key> /app/pki/edge.crt /app/pki/bundle.pem
```

It must contain the matching private-key block first and the `edge.crt`
certificate block second, be parseable by `openssl`, and have mode `0600`.

### 3) `/app/pki/bundle.meta.json` — provenance record

Valid JSON with exactly these keys:
```json
{
  "key_file":  "<path of the key file you bundled>",
  "cert_file": "<path of the certificate file you bundled>",
  "key_sha256":  "<sha256 hex digest of the key file bytes>",
  "cert_sha256": "<sha256 hex digest of the cert file bytes>"
}
```

## Edge cases the grader probes with fresh inputs

The grader generates **fresh key/certificate pairs** (formats and shapes you
have not seen), runs `python3 /app/mkbundle.py <key> <cert> <out>` on them,
and checks the produced bundle. Your tool must:

1. Bundle a fresh PKCS#8 RSA key + matching cert correctly (key block first,
   parses, key matches cert, mode `0600`).
2. Bundle a fresh **EC** key + matching cert correctly.
3. **Refuse a mismatched pair**: given a key whose public key does not match
   the certificate's, exit non-zero and create no output file.
4. Tolerate input files with stray text around the PEM blocks and CRLF line
   endings, producing a clean bundle.

## Rules

- Work only inside `/app`. Do not modify anything under `/app/pki/` except
  creating `bundle.pem` and `bundle.meta.json`.
- No network access. Standard library plus the `openssl` CLI.
- The grader runs `/app/mkbundle.py` unchanged on unseen key material — do
  not hard-code to the provided files.
