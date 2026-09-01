# Locker password recovery (hash-crack then unseal)

The CI artifact locker for project **indigo** has been sealed and the
passphrase only survives as a **SHA-256 digest**. You must run a CPU
password-cracker over that digest, use the recovered passphrase to unseal the
encrypted archive, and record the recovered values.

## Environment

- Working directory: `/app`. It already contains:
  - `/app/passwd.hash` — the digest: a single line with the lowercase
    40...64-hex **SHA-256** of the passphrase (64 hex characters), computed as
    plain `sha256(passphrase.encode("utf-8"))` — no salt, no separators.
  - `/app/wordlist.txt` — the candidate wordlist, one passphrase per line
    (the true passphrase is guaranteed to be one of its lines).
  - `/app/locker.zip` — an encrypted ZIP archive (legacy ZipCrypto, stored
    entries) whose single member holds the release notes. Python's
    `zipfile` opens it with `pwd=<passphrase>`.
- Python 3.12 is available as `python3`. Standard library only.
- **Do not modify `/app/passwd.hash`, `/app/wordlist.txt`, or
  `/app/locker.zip`.**

## Deliverables (both required)

1. `/app/crack.sh` — an executable shell script (runnable as
   `bash /app/crack.sh ...` and, after `chmod +x`, directly) with this
   interface:

   ```
   bash /app/crack.sh <hash_file> <wordlist> <zip_file> <out_dir>
   ```

   It must:

   - Read the target digest from `<hash_file>` (first non-empty line,
     trimmed, compared case-insensitively).
   - **Crack** it on CPU: hash every candidate in `<wordlist>` with SHA-256
     (one candidate per line, stripped of trailing whitespace/CR) and find the
     line whose digest equals the target. Do not hard-code passwords.
   - Use the recovered passphrase to open `<zip_file>` and extract its single
     member into `<out_dir>/<member-name>` (member content must be the
     decrypted original).
   - Write `<out_dir>/answer.json` with **exactly** these keys:

     ```json
     {
       "password": "<recovered passphrase>",
       "hash": "<target digest as read, lowercased>",
       "member": "<member name inside the zip>",
       "code": "<value after the `code=` line in the member>"
     }
     ```

     `code` is the text immediately following `code=` on that line, trimmed.
   - Exit `0` on success. If the digest is not cracked, extract fails, or the
     member has no `code=` line, exit non-zero and do not write a wrong
     `answer.json`.

   You may implement the cracking/extraction in an embedded `python3 -` heredoc
   or a helper Python file you create — but `/app/crack.sh` must be the
   entry point that works on any conforming inputs.

2. Run the deliverable on the visible fixtures so that:

   ```
   bash /app/crack.sh /app/passwd.hash /app/wordlist.txt /app/locker.zip /app
   ```

   produces `/app/answer.json` (and the decrypted member
   `/app/release_notes.txt`) for the visible case.

## Edge cases the grader probes with hidden fixtures

- The verifier mints **fresh** hash/wordlist/archive triples — different
  passphrases (never the visible one), different member names, different
  member contents and `code=` values, different wordlist sizes — copies them
  under `/tmp`, and runs your `/app/crack.sh` unchanged against them.
- Wordlist lines may have trailing `\r` (CRLF) or stray surrounding spaces;
  candidates must be stripped before hashing. Blank lines are skipped.
- The hash file may contain trailing whitespace/newlines; the digest compare
  must be case-insensitive on both sides.
- The member content always contains exactly one `code=` line; other lines
  vary and may themselves contain `=`.
- Wordlists are small (hundreds to a few thousand lines): a plain CPU loop
  over `sha256` finishes far inside the time budget. No GPU, no network.

## Constraints

- Work in `/app`. Do not modify the provided fixtures.
- The cracker must genuinely derive the passphrase from the digest — a
  hard-coded or guessed passphrase fails the hidden cases.
