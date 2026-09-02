# Vine Mantle — Security Recovery & Hardening

You are on a red/purple-team engagement for **Mantle LLC** against the extinct
"Vine Co-op". You recovered a disk image. Your job is to (A) recover credentials
from an encrypted vault and record them, (B) sanitize a leaked secret out of a
tracked git repo without disturbing any other file, (C) find and patch a
vulnerable Java jar-upload filename resolver and ship a rebuilt runtime jar, and
(D) provision a domain-named TLS certificate/key pair into a conventions
directory. All four sub-tasks must be completed; the verifier checks every one.

Work purely on CPU — every computation below is intentionally small and bounded.

---

## A. Recover credentials from the encrypted vault and record them

The vault archive is at `/app/vault/box.7z`. It is password-encrypted.

Read the three spec files under `/app/recovery/` and follow them exactly:

- `/app/recovery/format.txt` — the strict passphrase shape and its candidate space.
- `/app/recovery/seed.txt`  — how a candidate seeds a SHA-1 "subkey" digest.
- `/app/recovery/hash-rule.txt` — the subkey structural-count filter and the
  archive probing rule that pin down the single correct passphrase.

Do NOT guess or dictionary-attack. The intended path is:

1. **Enumerate.** Build the full candidate list from `format.txt` (see the exact
   shape; it is a tiny, fully enumerable space).
2. **Filter.** For each candidate compute the SHA-1 digest described in
   `seed.txt`, apply the structural rule from `hash-rule.txt`, and keep only the
   shortlist that satisfies it. The filter depends on the hexadecimal digest
   text exactly, letter-for-letter.
3. **Probe.** For the shortlist in ascending numeric order, probe the live
   archive header:
   ```
   7z t -y -p'<candidate>' /app/vault/box.7z
   ```
   The command exits `0` **only** for the correct passphrase. The first
   shortlist candidate that returns `0` is the vault passphrase.
4. **Extract.** Decrypt and extract the archive's single member file
   (`member.txt`) with p7zip (`7z x -y -o<dest> -p'<passphrase>'`).
5. **Parse.** `member.txt` contains two key/value lines of the form
   `app-username = VALUE` and `app-password = VALUE` (whitespace around the `=`
   is tolerated). Recover those two values.

Write the recovered credentials to BOTH of these files:

- `/app/answer.json` (UTF-8 JSON):
  ```json
  {"username": "<app-username VALUE>", "password": "<app-password VALUE>"}
  ```
- `/app/result/creds.txt` (UTF-8 plain text, one per line, `name: value`
  format, colon plus a single space):
  ```
  username: <VALUE>
  password: <VALUE>
  ```

### Deliverables for (A)

You MUST leave a runnable solver at `/app/solve.py` that reproduces the entire
pipeline for **any** vault that uses the same scheme (the same three spec files).
It must itself enumerate, filter, probe, extract, parse and write the outputs.
No hard-coded passphrase or credentials. It must be runnable like this:

```
python3 /app/solve.py [vault_path] [out_json]
```

- Default `vault_path` = `/app/vault/box.7z`
- Default `out_json` = `/app/answer.json`
- When `vault_path`/`out_json` are the defaults, it must ALSO (re)write
  `/app/result/creds.txt`.
- When given explicit non-default arguments, it must write only `out_json` and
  must not clobber `/app/result/creds.txt`.

The verifier will re-run `/app/solve.py` on a *second* encrypted archive of the
same scheme and diff the produced JSON, so it MUST generalize (no vault-specific
constants). It should not require any package beyond the std lib and the `7z`
binary.

## B. Sanitize a leaked secret from a git repo

A git repo lives at `/app/sanitize-repo/` (already initialized with history).
One secret string, the legacy daemon token, leaks on disk:

```
TKN-8v3K-99xq
```

The token appears in **exactly** the two contaminated tracked files:

- `/app/sanitize-repo/config/app.env`
- `/app/sanitize-repo/docs/mapping.md`

It may appear in a mix of upper/lower cases in those files (the token is matched
case-insensitively). All OTHER tracked files are clean and must not change.

Required:

1. Replace every occurrence of the token (any letter case) in those two files
   with the placeholder `REDACTED`. Leave the rest of each file's bytes intact.
2. Do not touch, reorder, or reformat any other file (no reindentation, no new
   trailing whitespace, no deletions/re-additions of files).
3. Keep the repo in a *clean* state: the working tree must still match the last
   commit except for the two intended edits, and the edits must be `git`-visible
   as changes to exactly those two paths (either staged or unstaged — either is
   fine, but they must be reflected in `git status`/`git diff`, not lost).
4. Prove abs exposure: case-insensitively search the whole working tree (ignoring
   `.git`) for the token; there must be zero hits.
   ```
   grep -ril 'TKN-8v3K-99xq' --exclude-dir=.git /app/sanitize-repo
   ```
   must print nothing.

## C. Patch the jar-upload filename resolver and rebuild the runtime jar

A small Java service `Lattice jar-dock` stores uploaded `.jar` builds. Its filename
resolver is intentionally vulnerable:

- Source package dir: `/app/jarupload/src/com/lattice/`
  - `JaxUpload.java` — contains a lone public static method
    `String resolve(String raw)` (the ONLY function you may change) plus a
    package/CONSTRUCTOR. Today it returns the client filename **verbatim**, which
    lets a hostile upload smuggle path separators and parent-dir components and
    write anywhere on the server.
  - `Probe.java` — a thin `main` harness that reads one filename per line from a
    file given as its first argument and prints `resolve(line)` per line. Do not
    edit `Probe.java`.

Patch `JaxUpload.resolve` so it returns ONLY the **base filename**, with this
exact sanitization, which the hidden harness will exercise:

1. Treat both `/` and `\` as path separators.
2. Also treat the percent-encodings `%2F`, `%2f`, `%5C`, `%5c` as separators
   (decode them first).
3. Drop empty components and the single-dot `.` component entirely.
4. A parent-directory component `..` is **neutralized** (dropped) — never allowed
   to climb upward.
5. Return the **last surviving component** — i.e. the final safe piece after all
   separators and dot/`.`-trivia are removed, which is the plain base name.
6. Never return a component containing a `/` or `\` (or percent-encoded
   separator) — the result must be a bare filename with no path, ever.
7. If nothing safe remains (e.g. the raw string is empty, all dots, or only
   dot/`..` components), return the fallback constant `upload.jar`.

`resolve` must never return `null` or throw.

After patching, **rebuild** the deliverable runtime jar at:

```
/app/dist/manta.jar
```

Build with javac/jar exactly so the harness class is runnable:

```
cd /app/jarupload/src
rm -rf /app/jarupload/build && mkdir -p /app/jarupload/build
javac -d /app/jarupload/build com/lattice/JaxUpload.java com/lattice/Probe.java
cd /app/jarupload/build && jar cf /app/dist/manta.jar com
```

Leave `/app/dist/manta.jar` in place (it is a checked deliverable). The verifier
will run:

```
java -cp /app/dist/manta.jar com.lattice.Probe <input-lines>
```

and compare each output line against the expected safe base name. Your patch
must make the released jar reflect the fix.

Illustrative cases (the hidden set is similar in kind, including edge/malformed):

| raw input                              | expected `resolve`  |
|----------------------------------------|---------------------|
| `../../etc/cron.d/renegade.jar`        | `renegade.jar`      |
| `..%5C..%5Cwindows%5Ccasper.jar`       | `casper.jar`        |
| `.%2Fcred%2F..%2Fpayload.jar`          | `payload.jar`       |
| `./.`                                  | `upload.jar`        |
| `reset.jar`                            | `reset.jar`         |

## D. Provision a domain-named TLS cert & key into a conventions directory

Create (self-signed is fine) a TLS certificate and its matching unencrypted RSA
private key for the host `portico.test`, and place them **at the conventions
directory** `/app/tls/` with domain-named filenames:

- `/app/tls/portico.test.crt` — a PEM x509 certificate whose Subject CN is
  exactly `portico.test`.
- `/app/tls/portico.test.key` — the PEM private key that matches the cert (same
  RSA modulus). Must NOT be passphrase-protected. File permissions: readable by
  the owning process, owner `0`-bit on group/other is recommended but not
  required.

Use `openssl` (available). e.g. keep the cert & key consistent with
`openssl x509 -noout -modulus` vs `openssl rsa -noout -modulus` matching.

---

## Acceptance criteria (what the verifier checks)

1. `/app/solve.py`, `/app/answer.json`, `/app/result/creds.txt` exist and their
   contents match the recovered credentials.
2. Re-running `/app/solve.py` on a fresh encrypted archive of the same scheme
   produces matching JSON (generalization).
3. The sanitize repo has changes to exactly the two contaminated paths, the
   token present is fully trace-free (case-insensitive), and no other file
   changed.
4. `/app/dist/manta.jar` runs `com.lattice.Probe` and correctly sanitizes the
   adversarial jar filenames (traversal, encoded separators, mask) to the
   expected base names.
5. `/app/tls/portico.test.crt` and `/app/tls/portico.test.key` exist, CN is
   `portico.test`, and priv-key/cert moduli match.

## Constraints

- Use the tools already installed in the image (python3, p7zip `7z`, openssl,
  git, java). No network access. No GPU.
- Do not delete or rename the supplied fixtures other than what the tasks require.
- You may not modify `/tests` or `/solution`. Everything you produce lives under
  `/app`.