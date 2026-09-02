# Zephyr vault recovery (red/purple team)

You are a red-team operator recovering a stranded Zephyr appliance tenant. Your
job has several independent parts. Read `/app` carefully before writing code.
**Do not modify** `/app/zephyr_gen.py` or `/app/vault.7z`. **Never read
`/tests`** — its contents are irrelevant to your work and are hidden.

All paths, file names, formats and edge cases below are exact. Follow them.

---

## Deliverables (create / finish all of these)

| Path | Meaning |
|------|---------|
| `/app/solve.py` | your solver; must run as `python3 /app/solve.py` and regenerate every downstream artifact (below) |
| `/app/candidates.txt` | one well-formed flare passphrase per line (see Part 1) |
| `/app/vault.hash` | the password-hash probe output of the archive (see Part 3) |
| `/app/creds.txt` | the decrypted member file extracted from the vault (see Part 4) |
| `/app/answer.json` | the recovered-credentials result (see Part 5) |
| `/app/scrub.py` | a reusable secret scrubber (see Part 6) |
| `/app/team/` | the shipped repo, with the leaked secret removed (see Part 6) |
| `/app/upload/sanitizer.py` | already present, but FLAWED; patch it (see Part 7) |

`/app/upload/sanitizer.py` and `/app/team/` already exist in the image.
`solve.py`, `scrub.py` and the derived text/JSON files do not.

---

## Part 1 — enumerate flare candidates (tight format + seed constraint)

The operator station schedule is `/app/zephyr_gen.py`. Read it. It defines:

- `commissioned(seed)` — whether a small integer `seed` is part of the active
  duty roster (a compact `subkey`/seed gate). Only commissioned seeds ever
  matter; the full seed space `[0, SEED_RANGE_HI)` is far larger and must not be
  brute-forced by trying all possible tokens.
- `emit_flare(seed)` — what the flaky station prints for that seed. It is not
  always a usable token.
- `is_well_formed(token)` — the exact flare format predicate.

A **candidate (well-formed flare token)** satisfies all of:

- exactly **24 characters**,
- only **uppercase letters (A–Z) and decimal digits (0–9)**,
- **begins** with the fragment `ZEPH`,
- **ends** with the fragment `CORE`.

Write `/app/solve.py` so that on each run it:

1. Scans **every commissioned seed** (honor `commissioned`; never try the naive
   full space), generates that seed's `emit_flare` output, and keeps **only the
   well-formed** ones (apply the format constraints above strictly).
2. Writes `/app/candidates.txt` with **each** retained candidate, one per line,
   in ascending seed order.
3. Exits 0.

You must retain any well-formed line; dropping the matching one by tightening
the format reasoning wins the whole task.

## 2 — SHA-1 structural beacon (select the vault passphrase)

The deployment ticket pinned the active flare's **field code `K = 17`**:

> The active (vault) passphrase is the **unique** candidate whose **SHA-1 hex
> digest letter-count equals `17`**, where the letter-count is the number of
> hex-letter characters `a b c d e f` present in the 40-character
> lowercase hex digest of the candidate string (UTF-8).

So for each candidate token, compute `sha1(token)` → hex digest (40 chars),
count how many are among `abcdef`. Exactly one candidate has that count equal to
`17`; that token is the **vault password** (`active_seed` is its seed).

## 3 — Password-hash probe of the protected archive

`/app/vault.7z` is an encrypted archive (AES-based, `7zAES`). Run a probe that dumps the archive's
encryption metadata into `/app/vault.hash`, demonstrating it is a crackable
protected target — for example, dump `7z l -slt /app/vault.7z` (which reports
`Method = ... 7zAES` and `Encrypted = +`). The file must be non-empty and must
reflect the AES encryption.

## 4 — Crack & extract the protected member

Using the active passphrase from Part 2, extract the archive's member file. The
archive decrypts (no GPU needed; the candidate set is small). Place the
**decrypted member** at `/app/creds.txt`. The member's content looks like:

```
operator-vault
user=<value>
secret=<value>
endpoint=<value>
role=<value>
```

`<value>` values are concrete strings; there is exactly one `user=`, one
`secret=`, one `endpoint=` line.

## 5 — Recovered-credentials result

Write `/app/answer.json` with **exactly and only** these keys:

```json
{
  "password": "<active vault passphrase>",
  "active_seed": <integer seed of the active passphrase>,
  "candidate_count": <number of lines written to /app/candidates.txt>,
  "beacon": 17,
  "probed": true,
  "member": "creds.txt",
  "creds_user": "<value after `user=`>",
  "creds_secret": "<value after `secret=`>",
  "endpoint": "<value after `endpoint=`>"
}
```

`creds_user`, `creds_secret`, `endpoint` must be read from the decrypted
`/app/creds.txt` you just recovered (a forged/hard-coded value fails).

## 6 — Scrub leaked secrets from the repo

`/app/team/` is a shared provisioning repo that inadvertently contains an
operator **credential literal** matching the token shape
`[A-Z0-9]{3}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{2}` (three groups: 3, 4, 4, then 2
uppercase/digit chars, dash-separated). Write a **reusable** scrubber
`/app/scrub.py` that generalizes past `/app/team/`:

- CLI: `python3 /app/scrub.py <rootdir>`.
- Scans every file in `<rootdir>`, finds every occurrence of a string matching
  the secret-token regex above, and **replaces** it with `[REDACTED]` (in place).
- **Deletes** files whose lower-cased extension is `.bak`, `.orig` or `.tmp`.
- Prints a concise JSON summary `{"removed": <count of replaced tokens>,
  "deleted": [<relative file paths>]}`.
- Exits `0`.

Run it on `/app/team/`. After you finish, `/app/team/` must contain **no**
string matching that regex anywhere (including inside backups) and the
`.bak`/`.orig`/`.tmp` files must be gone. Run it from a generic root too: hidden
evaluation copies fresh fixture trees to `/tmp` and reruns `/app/scrub.py`
against them — your scrubber must work on any directory, not just `/app/team`.

## 7. Patch the jar-upload filename filter

`/app/upload/sanitizer.py` is a Python port of the Java `UploadFilter` used by
the jar-upload endpoint. It currently only strips the directory component and
trusts the rest — a flaw. Patch the function `sanitize_upload_filename(raw)`
(keep its name and signature, and keep the module importable as
`from sanitizer import sanitize_upload_filename`) so it returns `""` when
unacceptable, and otherwise the untouched basename:

1. Return `""` for `None` and for a name that is empty or whitespace-only.
2. **Traversal:** return `""` if the name contains a path separator (`/` or
   `\`) or any dot-dot component (`..`).
3. **Mask:** return `""` if the name's **final extension** (the substring from
   the last `.` to end, lower-cased) is one of the dangerous set
   `DANGEROUS_EXTS = {".jsp", ".war", ".js", ".jspx", ".sh", ".bat"}`.
4. Otherwise return the cleaned basename unchanged (e.g. a `.jar`, `.zip`,
   `.json`, `.txt` name passes through).

You may keep the existing `DANGEROUS_EXTS` module constant (renamed or value
unchanged does not matter) as long as the module's function honors the above
for it. The verifier feeds fresh hidden names; your function must generalize
(edge inputs include `..`, `/abs/path`, backslash paths, double-extensions such
as `weapon.jar.jsp`, and plain safe names).

---

## Success

Your task is complete when: `/app/solve.py` runs standalone and produces the
downstream artifacts; `/app/creds.txt` equals the real decrypted member;
`/app/answer.json` matches the schema and the true credentials;
`/app/team/` is free of the leaked secret; and `/app/upload/sanitizer.py`
rejects traversal and masked names while accepting safe ones. The evaluation
re-runs `/app/solve.py`, re-extracts the archive from your `answer.json`
password, checks the candidate file, scrubs fresh directories, and runs the
upload harness on fresh inputs.