# Provision the artifact-mirror deploy key

You are on the offline provisioning host for an internal artifact mirror. The
security runbook requires a **machine-only deploy key**: an RSA private key
that never leaves the host, is never passphrase-protected (it must be usable
from an unattended service), and is readable only by its owner. You must
provide both a reusable generator script and the actual key it produces.

The `openssl` CLI is installed. There is **no network access**; do not attempt
any.

## Deliverables (both required, under `/app`)

1. **`/app/keygen.sh`** — an **executable** bash script with this interface:
   ```
   /app/keygen.sh <bits> <output_path>
   ```
   Behavior contract:
   - `bits` must be a decimal integer with `2048 <= bits <= 8192`. If it is
     missing, not a decimal integer (e.g. `fourk`, `4096x`), negative, zero,
     or outside that range (e.g. `1024`, `16384`), the script must print a
     diagnostic to **stderr** and exit with status **exactly `2`**, leaving
     the filesystem untouched (no output file may be created or modified).
   - On success it must generate an **unencrypted RSA private key** of
     exactly `<bits>` bits and write it in PEM form to `<output_path>`
     (either PKCS#8 `-----BEGIN PRIVATE KEY-----` or PKCS#1
     `-----BEGIN RSA PRIVATE KEY-----` is acceptable — but never an
     `ENCRYPTED` PEM).
   - The output file's mode must be **exactly `0600`** (owner read/write
     only), **regardless of the caller's umask** — do not rely on umask
     alone; set the mode explicitly.
   - If a file already exists at `<output_path>` it must be **overwritten**
     with the new key (and its mode set to `0600`).
   - Exit `0` on success. No network use, no interactive prompts.
2. **`/app/deploy_key.pem`** — the deploy key itself, produced by actually
   running your generator:
   ```
   /app/keygen.sh 2048 /app/deploy_key.pem
   ```
   It must be a valid, unencrypted, exactly-**2048-bit** RSA private key
   (`openssl rsa -check -noout` reports it as ok) with file mode `0600`.

## Hidden / edge cases the grader will probe

The grader executes `/app/keygen.sh` on inputs you have not seen, in scratch
directories, and checks for each: exit code, whether the output file was
created, its mode, that the key parses as unencrypted RSA of the requested
size, and key validity. Expect at least:

- accepted sizes (e.g. `2048`, `4096`) — must succeed with the right bit
  length and mode `0600`, including under a permissive umask such as `000`;
- rejected sizes (`1024`, `16384`) and invalid sizes (`0`, negative,
  non-numeric strings) — must exit `2` and create nothing;
- a pre-existing junk file at the output path (mode `0644`) — must be
  replaced by a valid key with mode `0600`.

## Rules

- Do not modify anything outside `/app` (scratch temp files aside).
- No network access at any point.
- The key material itself is random — only the documented properties
  (algorithm, bit length, encryption state, file mode, exit codes) are
  checked, never the bytes.
