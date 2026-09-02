# Local trust bundle: build and inspect

You are in a small offline box (Python 3.12, the `cryptography` library, and the
`openssl` CLI are installed; no network). Create a self-signed certificate and key,
then build a small **reusable** tool that inspects arbitrary X.509 certificates —
the tool must work on inputs you have never seen.

## Input contract (do NOT modify)

`/app/dates.txt` describes the intended validity of your certificate:

```
start=2031-04-02T00:00:00Z
days=30
```

Each line is `key=value`; comment lines starting with `#` and blank lines may occur.
`start` is an ISO-8601 UTC timestamp, `days` is a whole positive integer.

## Deliverables (all under `/app`)

1. **`/app/cert.pem`** — a self-signed X.509 certificate with:
   - subject `CN=example.internal`;
   - exactly one SAN, `DNS:example.internal`;
   - `notBefore` exactly equal to the UTC `start` in `dates.txt`, and
     `notAfter` exactly `days` calendar days later (i.e. valid for exactly
     `30` days from `2031-04-02T00:00:00Z`);
   - an RSA public key of at least 2048 bits.
2. **`/app/key.pem`** — the matching private key, **unencrypted** (no passphrase/encryption),
   written with file mode `0600` (readable and writable only by its owner). The
   public key it contains must equal the public key in `cert.pem`.
3. **`/app/certinspect.py`** — a reusable command-line tool with this exact interface:
   ```
   python3 /app/certinspect.py <cert.pem> <dates.txt> <out.json>
   ```
   It must read the given certificate and the given dates contract, and write a
   well-formed JSON object to `<out.json>` with exactly these five keys:
   - `"subject"` — the certificate's Distinguished Name as an **RFC 4514 string**
     (the form produced by `cryptography`'s `Name.rfc4514_string()`, e.g.
     `"CN=example.internal"` or `"OU=Platform,O=Acme,CN=edge.internal"`);
   - `"san"` — an **ordered** list of the SAN entries present, each formatted as
     `TYPE:VALUE` where `TYPE` is one of `DNS`, `IP`, `email`, `URI`, `dirName`
     (e.g. `["DNS:mail.internal","IP:10.20.30.40"]`). If the Subject Alternative
     Name extension is absent, this must be `[]`.
   - `"key_algorithm"` — the certificate's public-key algorithm, exactly one of
     `"RSA"`, `"ECDSA"`, or `"Ed25519"`;
   - `"valid_days"` — the whole number of calendar days between `notAfter` and
     `notBefore` (i.e. `(notAfter - notBefore).days`, fractional parts floored);
   - `"dates_match"` — `true` if and only if `notBefore` equals the UTC `start`
     parsed from the dates file **and** `valid_days` equals its `days`; otherwise
     `false`.
4. **`/app/cert-report.json`** — the JSON report produced by actually running
   `/app/certinspect.py /app/cert.pem /app/dates.txt /app/cert-report.json`.

## Edge cases your tool MUST handle (these are exercised on fresh inputs)

- Certificates with **multiple SANs**, SANs of **mixed types** (DNS, IP, email,
  URI), and certificates with **no SAN at all** (report `[]`).
- Different key algorithms: RSA, ECDSA, and **Ed25519**.
- Subjects with **multiple RDNs** (e.g. built as CN then O then OU, which renders
  as `"OU=...,O=...,CN=..."` in RFC 4514 form).
- Validity periods with a **fractional** component (e.g. `45` days plus `6` hours):
  `valid_days` must be the floored whole-day count.
- A dates file whose `start` / `days` do **not** match the certificate's actual
  validity — in that case `dates_match` must be `false`.
- Callers may pass any path for the output; your tool must create/overwrite it and
  exit non-zero if the certificate or dates file is unreadable/malformed.

## Rules

- Do **not** modify files you did not create (`dates.txt` in particular) and do not
  modify the input certificates/dates files passed to `certinspect.py`.
- Do not use the network.
- `certinspect.py` must be executable and run from a fresh shell exactly as documented
  above; it must not depend on files you created for the visible case.
