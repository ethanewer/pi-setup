# Halcyon Diagnostics — sealed compliance export

You are the night-shift compliance engineer at **Halcyon Diagnostics**. Before
the courier arrives, the nightly export under `/app/exports` must be sealed
into a **GPG symmetric-encrypted archive** so that no unencrypted copy of the
patient data ever leaves the machine. Build the sealing pipeline now; the
auditor (grader) will later swap in *different* export contents and a
*different* passphrase file and re-run your pipeline unchanged.

## Environment

- Working directory `/app` contains:
  - `/app/exports/` — the clinical export tree (CSV files, nested
    subdirectories).
  - `/app/.seal-key` — the passphrase file (a single line).
- `gpg`, `tar`, `gzip`, `find` and a POSIX shell are installed. Offline.
- **Do not modify `/app/exports/` or `/app/.seal-key` yourself** — your script
  must read them as-is.

## Deliverables (all required)

1. **`/app/seal.sh`** — an executable sealing script. It must work when run
   from any working directory, both as `bash /app/seal.sh` and as
   `./seal.sh`, and must perform the steps below in order.
2. **`/app/records.gpg`** — the sealed archive produced by running your script
   on the visible fixtures.
3. **`/app/cipher-choice.txt`** — one short token naming the strongest
   symmetric cipher `gpg` offers, discovered from the tool's own
   documentation (`man gpg`). The expected value names **AES-256** (accept:
   `AES256` or `AES-256`).

## What `/app/seal.sh` must do (in order)

1. Read the passphrase from the file `/app/.seal-key` (do **not** hard-code the
   passphrase text; use `gpg --passphrase-file`).
2. Build a **deterministic** plaintext snapshot of `/app/exports`: a `tar`
   with reproducible metadata (at minimum `--sort=name`, a fixed `--mtime`,
   and normalized owner/group) piped through `gzip -n` (no timestamp in the
   gzip header). Write this transient plaintext archive **only under `/tmp`**.
3. Write the discovered strongest symmetric cipher name to
   `/app/cipher-choice.txt`.
4. Seal the snapshot with **exactly AES-256** symmetric encryption and the
   strongest key-stretching S2K digest:
   ```
   gpg --batch --yes --pinentry-mode loopback \
       --passphrase-file /app/.seal-key \
       --symmetric --cipher-algo AES256 --s2k-digest-algo SHA512 \
       --output /app/records.gpg <snapshot>
   ```
5. **Remove every plaintext intermediate** before exiting: no `.tar`,
   `.tar.gz`, `.tgz`, or other plaintext snapshot may remain anywhere under
   `/app` or `/tmp`.

The sealed file `/app/records.gpg` must decrypt (with whatever passphrase file
is present at `/app/.seal-key` at decryption time) to a snapshot whose
extracted contents are **byte-for-byte identical** to `/app/exports`.

## Audit checks the grader performs (all must pass)

- Decrypts `/app/records.gpg` with the current `/app/.seal-key` and extracts
  it; the extracted tree must match `/app/exports` exactly (same relative file
  set, identical bytes) regardless of the top-level directory name used inside
  the tar.
- Confirms the OpenPGP packets of `/app/records.gpg` report **cipher 9
  (AES-256)** — i.e. `--cipher-algo AES256` was genuinely used, not the gpg
  default.
- Confirms `/app/cipher-choice.txt` names AES-256.
- Scans `/app` and `/tmp` for leftover plaintext archives (`.tar`, `.tar.gz`,
  `.tgz`, `.gz`) — any leftover fails the audit.
- **Hidden reruns:** the grader modifies `/app/exports` (adds and changes
  files, including a nested subdirectory), replaces `/app/.seal-key` with a
  different passphrase, re-runs `bash /app/seal.sh`, and repeats every check
  above against the new state. Your script must therefore derive everything
  from the live `/app/exports` and `/app/.seal-key` — never from the visible
  contents or the visible passphrase.

## Constraints

- No network access; use only the preinstalled tools.
- The script must exit 0 on success and must not leave temp files behind on
  success.
