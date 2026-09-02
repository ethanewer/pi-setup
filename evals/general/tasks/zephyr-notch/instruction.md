# Project Zephyr decommission

You are engineering the teardown of a data-centre rack. Two responsibilities
are yours before the auditors arrive: destroy the sensitive vault so no
recoverable bytes remain, and recover a sealed handoff message, recording its
exact content. Everything you ship must be reusable, because the exact same
steps will be re-run on freshly generated material later.

Work only inside `/app`. The detailed plan is in `/app/data/notes.rst` and the
handoff explanation is in `/app/handoff/manifest.txt`.

## Responsibilities

### 1. Secure-erase the vault (write `/app/secure_erase.sh`)

The sensitive area is the directory tree rooted at `/app/vault`. It may
contain nested directories, a dot-prefixed hidden file, and future files with
awkward names. You must author **one reusable, argument-driven program**

```
/app/secure_erase.sh TARGET_DIR [MARKER_FILE]
```

that destroys `TARGET_DIR` completely and safely:

* **Overwrite first.** For every regular file anywhere under `TARGET_DIR`
  (including hidden dot-files, read-only files, and files with spaces in their
  names), overwrite the file's contents *in place* at least once with a
  genuine secure-deletion mechanism (for example `shred`, or writing zeros or
  random bytes through `dd`, or truncating-and-filling via a destructive
  write such as `cat /dev/zero > file`) **before** the file is unlinked. The
  goal is that the original bytes cannot be picked back off the media. A plain
  `rm`/`unlink` with no prior overwrite does **not** satisfy this.
* **Then remove everything.** Unlink every file and remove every (now-empty)
  directory recursively, and finally remove `TARGET_DIR` itself.
* **Neighbors are sacred.** Do **not** touch anything outside `TARGET_DIR`.
  Sibling files or directories, or a relative `..`/wildcard that walks out of
  the tree, are forbidden.
* **Handle awkward members generically:** dot-prefixed hidden files,
  read-only files, filenames containing spaces, empty (sub)directories, and a
  broken symbolic link pointing nowhere must all be removed without aborting
  the erase (empty directories are simply removed).
* **Never follow a symlink out of the tree** while erasing, and never delete
  anything the tree does not contain.
* **Idempotent on a missing target.** If `TARGET_DIR` does not exist, treat it
  as already erased: exit `0` and do not raise an error (still write the marker
  when one is given).
* Exit `0` only on full success. If the erase fails, exit non-zero.
* When `MARKER_FILE` is given and erasure (or the no-op case) succeeds, write
  the marker file containing exactly the bytes `OK\n` (the two characters `OK`
  and a single newline).

After authoring the script, run it on the shipped vault to produce the second
deliverable:

```
bash /app/secure_erase.sh /app/vault /app/erased_ok.txt
```

This must leave `/app/data/activity.log` and `/app/data/notes.rst`
byte-for-byte identical to how they started. The sensitive tree is
`/app/vault`; the neighboring files that must survive live in `/app/data/`.

## 2. Determine the tool's capability and recover the message

Read `/app/handoff/manifest.txt`. The payload `/app/handoff/msg.enc` was
sealed with the **OpenSSL symmetric stream/block command** (`enc`) using the
AES-256 counter-mode cipher (a streaming mode, no padding). The 256-bit key
and IV are hex-encoded in `/app/handoff/key.hex` and `/app/handoff/iv.hex`.

* **Consult the manual before applying.** Open the manual page that shipped
  with the tool — `man openssl-enc` — and read its list of supported ciphers
  to find the **exact option spelling** for the AES-256 counter-mode cipher.
  Do not guess from memory; the manual is the authoritative source for the
  option token. (Look for a token of the form `-aes-256-ctr`.)
* Record your finding in a new file **`/app/capability_notes.md`**. It must
  contain a line with exactly this layout:
  ```
  cipher option: <OPTION>
  ```
  where `<OPTION>` is the **exact** openssl option token you identified from
  the manual (for example `-aes-256-ctr`). You may add any other explanatory
  prose you like underneath.
* **This finding is what gets re-applied later.** The exact option token you
  record in `capability_notes.md` is the knowledge the operator will reuse to
  unseal *other* messages sealed with the same cipher (with different keys and
  IVs), so it must be the real, man-page-derived token, not a coincidence.
* **Apply it to recover the payload.** Decrypt `/app/handoff/msg.enc` with the
  identified option:

  ```
  openssl enc -d <OPTION> -K <contents of key.hex> -iv <contents of iv.hex> \
      -in /app/handoff/msg.enc -out <recovered>
  ```
* Read the recovered plaintext message.

## 3. Resulting deliverable `/app/results.txt`

Write the **exact recovered plaintext message**, byte-for-byte (same spacing,
same casing, no added leading/trailing whitespace and no omitted characters),
into **`/app/results.txt`**. A single trailing newline is acceptable; nothing
else. Any typo, extra space, or re-wording fails the check.

## Deliverables (your final answer)

1. `/app/secure_erase.sh` — executable, reusable secure eraser (must be usable
   on fresh target directories with new file sets).
2. `/app/erased_ok.txt` — the marker produced by erasing `/app/vault`. Its
   bytes MUST be exactly `OK\n`.
3. `/app/capability_notes.md` — documents the exact cipher option you found in
   the manual (line format described above).
4. `/app/results.txt` — the exact recovered final message, byte-for-byte.

## Rules

* Only bash and the standard tools already installed (`coreutils`, `openssl`,
  `python3`, `man`) may be used. No network, no additional installs.
* Do **not** modify anything under `/app/handoff/`, and do not modify
  `/app/data/activity.log`, `/app/data/notes.rst`, or any file outside
  `/app/vault` during the erase step.
* Your `secure_erase.sh` must be fully general — it will be run against fresh
  hidden target directories containing different files, edge cases, and even
  a missing target.
* Nothing about `/app/tests/` is visible to you. Solve entirely from this
  document and the shipped files.