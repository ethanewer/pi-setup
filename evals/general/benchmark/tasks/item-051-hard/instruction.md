# Item-051 (hard) — Issue a correct, secure RSA-2048 / X.509 end-entity
# certificate and prove by inspection that it matches the security spec

You are a TLS/infrastructure engineer for a health-systems vendor. Your
on-premise appliance must present a self-issued RSA-2048 endpoint identity for
the name `api.secure.example.test`. Do **not** trust any prior tooling output:
a number of legacy scripts in the environment report `SUCCESS` while silently
producing weak or malformed material. Your job is to translate the written
security requirements below into concrete OpenSSL flags, generate fresh
artifacts, and then **inspect the generated artifacts themselves** (not the
exit status of any tool) to prove they satisfy every requirement.

## Environment (read-only reference material)

- `/workspace/requirements.md` — the authoritative security spec you must satisfy.
- `/workspace/gen_cert.py` — a legacy "certificate issuer" that reports success
  but produces an insecure certificate (weak key, weak digest, wrong extensions,
  wrong subject). It is provided as a trap. Never assume its output is correct;
  verify and replace it.

Everything your deliverable certs must satisfy is in `/workspace/requirements.md`
— read it. Do not rely on the legacy script.

## Deliverables (files you must produce in `/app`)

1. `/app/tls.key.pem` — an **unencrypted, no-passphrase** RSA private key in PEM
   (PKCS#8 or PKCS#1) with modulus size exactly **2048 bits** and public exponent
   **65537**.
2. `/app/tls.cert.pem` — a **self-signed** X.509 certificate (issuer == subject
   on the key) that PAIRS the key:
   - subject: `CN=api.secure.example.test, O=Acme Laboratories, C=US`
   - signature algorithm `sha256WithRSAEncryption`
   - validity length exactly **730 days** (24 months) starting from generation;
     certificate must be usable now (`-checkend 0` passes)
   - `subjectAltName` (SAN) including **all three** of: `DNS:api.secure.example.test`,
     `DNS:alt.secure.example.test`, and `IP:198.51.100.7`
   - `keyUsage` critical, containing `digitalSignature` and `keyEncipherment`
   - `extendedKeyUsage` containing `serverAuth`
   - `basicConstraints` critical, `CA:FALSE`
   - the SPKI public key must exactly match private key `/app/tls.key.pem`
   - serial number is a positive value < 2**20
3. `/app/tls.report.txt` — a proof of **artifact inspection** (not tool return
   codes). Use `openssl` to read the actual bytes of the files you produced and
   record, one per line:
   ```
   subject=CN=api.secure.example.test, O=Acme Lab, C=US
   issuer=CN=api.secure.example.test, O=Acme Lab, C=US
   sig_alg=sha256WithRSAEncryption
   rsa_bits=2048
   fingerprint=<sha256 hex fingerprint of the cert, colon-separated uppercase>
   spki_sha256=<hex sha256 of the DER-encoded subject public key>
   VERIFIED=yes
   ```
   The harness will recompute these fingerprint values from your actual files, so
   they must be real (copying the legacy script's claimed values will fail).

The `VERIFIED=yes` line must appear only after you have confirmed with a genuine
`openssl` certificate-dump that every extension in `requirements.md` is actually
present.

## Success criteria

- `openssl x509 -in /app/tls.cert.pem -noout` parses.
- key size 2048, exponent 65537; certificate public key and private key match.
- subject/issuer correct; signature sha256WithRSAEncryption.
- validity ~730 days and currently valid.
- SAN, keyUsage, extendedKeyUsage, basicConstraints all present and correct.
- `/app/tls.report.txt` matches the real certificate fingerprints.
- private key is PEM and unencrypted (`openssl pkey -in ... -noout -check` ok).