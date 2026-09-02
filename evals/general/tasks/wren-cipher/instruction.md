# Evidence vault sealing — symmetric AES-256 archive hygiene

You are the custodian of case **2026-HL-0187**. The sealed snapshot of the
evidence directory must ship to the regional vault as a **single symmetric
GPG archive encrypted with AES-256**, and the workstation must be left clean:
no unencrypted snapshot may survive anywhere.

Everything lives under `/app`:

- `/app/evidence/` — the evidence directory (files + subdirectories) to seal.
- `/app/.seal-key` — the passphrase file (one line; strip the trailing newline
  when a passphrase is needed).

`gpg` (GnuPG), `tar`, `gzip` and GNU coreutils are installed. Do **not**
modify anything under `/app/evidence/` or `/app/.seal-key`.

## Deliverables

1. `/app/seal.sh` — an **executable** sealing script. It must work both when
   invoked directly (`/app/seal.sh ...`) and via `bash /app/seal.sh ...`:
   ```
   seal.sh [SRC_DIR] [OUT_GPG] [PASS_FILE]
   ```
   - Defaults when an argument is omitted: `SRC_DIR=/app/evidence`,
     `OUT_GPG=/app/evidence.gpg`, `PASS_FILE=/app/.seal-key`.
   - It must work for **any** source directory and passphrase file passed as
     arguments, not just the visible fixture.

2. `/app/evidence.gpg` — the ciphertext produced by running your script on the
   visible fixtures (defaults above).

3. `/app/cipher.txt` — the name of the strongest symmetric block cipher `gpg`
   offers for `--cipher-algo`, one token, no spaces (e.g. `AES256`; the
   hyphenated `AES-256` spelling is also accepted). Consult `man gpg` for the
   cipher list.

## What seal.sh must do (implement exactly)

1. Build the plaintext snapshot of `SRC_DIR` as a **tar archive** (gzip is
   allowed) and place that transient plaintext archive **only under `/tmp`** —
   never inside `/app` and never at any other permanent location.
2. Seal it with symmetric encryption using **exactly**:
   - `--symmetric`
   - `--cipher-algo AES256`
   - `--s2k-digest-algo SHA512`
   - batch/loopback operation with the passphrase read from `PASS_FILE`
     (e.g. `--batch --yes --pinentry-mode loopback --passphrase-file ...`)
   writing the ciphertext to `OUT_GPG`.
3. **Remove every plaintext intermediate** before exiting: after `seal.sh`
   returns, no `.tar`, `.tar.gz`, `.tgz`, or other cleartext snapshot may
   remain anywhere under `/app` or `/tmp`.

Decryption of the produced file with `PASS_FILE` must yield a tar archive
whose extraction reproduces `SRC_DIR` byte-for-byte (including subdirectories
and binary files).

## How this is graded

The verifier re-runs `/app/seal.sh` (both invocation styles, and with
**different hidden source directories and passphrase files**), then:

- decrypts each ciphertext with the matching passphrase file and diffs the
  extracted tree against the source directory (byte-for-byte),
- inspects the OpenPGP packets and requires the symmetric cipher to be
  **9 (AES256)** and the S2K hash to be **10 (SHA512)**,
- decrypting with a **wrong** passphrase must fail,
- checks `/app/cipher.txt` names AES-256,
- scans `/app` and `/tmp` and fails if any plaintext archive (`*.tar`,
  `*.tar.gz`, `*.tgz`) survives.

## Constraints

- No network access; everything runs offline in the container.
- Keep the exact deliverable paths listed above.
