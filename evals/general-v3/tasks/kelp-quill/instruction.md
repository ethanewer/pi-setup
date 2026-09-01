# Provision the Heron relay deployment key

You are on an **offline** provisioning box (Python 3.12 with the `cryptography`
library and the `openssl` CLI installed; no network). The Heron relay pipeline
needs its deployment signing key provisioned to policy, plus a small
**reusable** key-inspection tool that must work on PEM private keys you have
never seen.

## Policy (do NOT modify)

`/app/key_policy.txt` states the deployment key policy:

```
# heron relay deploy key policy
bits=2048
dir_mode=0700
key_mode=0600
pub_mode=0644
```

## Deliverables (all required, under `/app`)

1. **`/app/keys/deploy_key.pem`** — a freshly generated RSA private key:
   - exactly **2048** bits;
   - **unencrypted** (no passphrase/encryption; must load with
     `password=None`);
   - file mode exactly `0600`, and the containing `/app/keys/` directory mode
     exactly `0700`.
2. **`/app/keys/deploy_key.pub`** — the matching public key in
   SubjectPublicKeyInfo PEM form (`-----BEGIN PUBLIC KEY-----`), byte-matching
   the public half of `deploy_key.pem`, with file mode exactly `0644`.
3. **`/app/keyreport.py`** — a reusable command-line tool with this exact
   interface:
   ```
   python3 /app/keyreport.py <private_key.pem> <out.json>
   ```
   It reads the given PEM private key file and writes a JSON object to
   `<out.json>` with exactly these keys:
   - `"algorithm"` — `"RSA"`, `"EC"`, or `"Ed25519"` per the key type;
   - `"bits"` — the key size in bits (for RSA, the modulus size; for EC, the
     curve size; for Ed25519, `256`);
   - `"encrypted"` — `true` if and only if the PEM file is an encrypted
     private key (i.e. it cannot be loaded with `password=None`); otherwise
     `false`;
   - `"fingerprint"` — for unencrypted keys: the SHA-256 digest of the
     **DER encoding of the key's SubjectPublicKeyInfo** public key, formatted
     as uppercase hex byte pairs separated by colons (e.g.
     `"9B:C5:25:5C:...:07"`, 32 bytes → 32 pairs). For encrypted keys, where
     the public half cannot be extracted without the passphrase: `null`.
   - For an **encrypted** key, `"algorithm"`, `"bits"`, and `"fingerprint"`
     must all be `null` and `"encrypted"` must be `true`.
   - If the input file is missing, unreadable, or cannot be parsed as a PEM
     private key, the tool must exit with a **non-zero** status and must not
     write a report file.
4. **`/app/deploy-report.json`** — the JSON report produced by actually
   running `/app/keyreport.py /app/keys/deploy_key.pem /app/deploy-report.json`.

## Rules

- Do **not** modify `/app/key_policy.txt`.
- Do not use the network.
- `keyreport.py` must work on any conforming input path (the grader runs it on
  private keys you have not seen, including keys of other algorithms and
  encrypted keys), so do not hard-code to the visible key.
- The grader independently re-checks the key length, encryption state, file
  modes, key/public match, and the fingerprint against its own computation.
