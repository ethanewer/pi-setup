# Stage TLS identity bundles for the artifact registry

An on-prem **artifact registry** is being brought up with mTLS, and you are on
provisioning duty. Every service identity on this network is shipped as a
**combined PEM bundle**: a single file whose first PEM block is the private
key and whose second PEM block is the matching X.509 certificate. The registry
refuses to start from a bundle that is malformed, mismatched, or has the
blocks in the wrong order — so this step must be exact.

## Environment

- Working directory: `/app`. Ubuntu base with the `openssl` CLI and Python
  3.12 (`python3`) available; **no network**.
- `/app/staging/identity-spec.toml` — the visible identity's spec (common
  name and key size). Read-only: **do not modify anything under
  `/app/staging/`**.

## Deliverables (all required)

1. `/app/mkcert.py` — a runnable Python program with this interface:
   ```
   python3 /app/mkcert.py --cn <COMMON_NAME> --bits <BITS> --out-dir <DIR>
   ```
   For any common name and any `BITS` of **2048** or **4096**, it must create
   `<DIR>` (if missing) and generate inside it:
   - `key.pem` — the RSA private key in PEM format (PKCS#8 `BEGIN PRIVATE
     KEY` or PKCS#1 `BEGIN RSA PRIVATE KEY`, either is accepted);
   - `cert.pem` — a self-signed X.509 certificate (PEM) whose subject common
     name (CN) is exactly `<COMMON_NAME>` and whose public key matches
     `key.pem`;
   - `bundle.pem` — the **combined PEM**: the private-key block first, then
     the certificate block, concatenated (standard `-----BEGIN ...-----` /
     `-----END ...-----` PEM armor, newline after each `END` line);
   - `fingerprint.txt` — a single line: the SHA-256 digest of the
     certificate's DER encoding as 64 lowercase hex characters (no colons).
   `key.pem` and `bundle.pem` must be written with file mode `0600`.

2. The **visible identity**, provisioned exactly per the staging spec:
   ```
   python3 /app/mkcert.py --cn registry.internal --bits 2048 --out-dir /app/identity
   ```
   producing `/app/identity/key.pem`, `/app/identity/cert.pem`,
   `/app/identity/bundle.pem`, and `/app/identity/fingerprint.txt`.

## Hidden-case contract

The grader runs your program **unchanged** on identities you have never seen
(different common names, both key sizes, and output directories that do not
exist yet) and then validates each result with `openssl`:

- `key.pem` and `cert.pem` parse individually; the certificate's subject CN
  equals the requested common name; the certificate's public key equals the
  private key's public key; the RSA key size equals the requested `BITS`.
- `bundle.pem` contains **exactly two** PEM blocks: a private-key block
  first, then a certificate block. Each block parses standalone when
  extracted; the bundled key and cert match each other and the case's CN.
- `key.pem` and `bundle.pem` have mode `0600`.
- `fingerprint.txt` equals the lowercase-hex SHA-256 of the certificate DER.
- The certificate is currently valid (`openssl x509 -checkend 0` passes).

## Constraints

- No network access. You may use the `openssl` CLI via `subprocess`, or the
  `cryptography` library if available — anything that satisfies the contract.
- Do not modify `/app/staging/`. `/tests` and `/solution` are not available
  to you.
- A bundle with the certificate before the key, a key that doesn't match its
  cert, a missing or colomorphic fingerprint, or loose file modes all fail
  verification.
