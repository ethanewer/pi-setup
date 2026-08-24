# Item-051 (medium) — Generate and inspect a correct TLS server certificate

The security office is provisioning a TLS server certificate for an internal
appliance. They have handed you a **requirements spec** and expect you to turn
those requirements into the correct cryptographic primitives, produce PEM
artifacts, and — critically — **verify the generated artifacts by inspecting
them**, never merely trusting that a command exited zero.

## Security requirements (the spec)

- Key type: **RSA**, key size **2048 bits** (no weaker defaults).
- Certificate: **self-signed X.509**.
- Subject common name: `server.example.com`.
- **Subject Alternative Names (SANs)** must include ALL of:
  - `DNS:server.example.com`
  - `DNS:api.example.com`
  - `DNS:admin.example.com`
- Signature algorithm: **SHA-256** (must not be the weak SHA-1 default).
- Valid for **365 days** from now.
- Both the private key and the certificate must be **PEM** files, and the
  certificate's public key must match the private key's public key.

## Deliverables

Create these two files under `/app/certs/`:

- `/app/certs/server.key` — the **unencrypted** RSA-2048 private key (PEM).
- `/app/certs/server.pem` — the **self-signed certificate** (PEM).

## Suggested approach

```bash
mkdir -p /app/certs
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
  -out /app/certs/server.key
openssl req -new -x509 -key /app/certs/server.key -sha256 -days 365 \
  -subj "/CN=server.example.com" \
  -addext "subjectAltName = DNS:server.example.com, DNS:api.example.com, DNS:admin.example.com" \
  -out /app/certs/server.pem
```

## Verify by inspecting (required)

Do not stop at exit code `0`. Run these and confirm each:

```bash
# 1. cert parses and shows the required properties
openssl x509 -in /app/certs/server.pem -noout -text | grep -E "Signature Algorithm|Public-Key|Subject:|Subject Alternative Name|DNS:"
# 2. key is RSA-2048
openssl pkey -in /app/certs/server.key -noout -text | grep "Private-Key"
# 3. the key matches the cert's public key (both hashes must be equal)
openssl x509 -in /app/certs/server.pem -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256
openssl pkey -in /app/certs/server.key -pubout -outform DER | openssl dgst -sha256
# 4. validity: notBefore <= now <= notAfter, 365-day span
openssl x509 -in /app/certs/server.pem -noout -startdate -enddate
```

Produce all deliverables, then self-review that every requirement above is
satisfied by what the artifacts actually say.

## Verifier checks (independent, artifact-only)

- `/app/certs/server.key` and `/app/certs/server.pem` both exist and parse.
- The cert subject is `CN = server.example.com`.
- The cert key is RSA **2048-bit**.
- The signature algorithm is **SHA-256** (not SHA-1).
- The SAN extension contains all three required DNS names.
- The private key is RSA 2048 and its public key matches the certificate.
- `openssl x509 -checkend` against a 30-day window passes (validity in force).

Do not modify anything other than creating `/app/certs/` and its two files.