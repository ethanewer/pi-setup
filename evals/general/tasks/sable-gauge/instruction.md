# Build a reproducible tape bundle with a stable identity digest

The archive team needs **byte-reproducible** tar bundles: the same input tree
must always produce the exact same archive bytes and the same digest, on any
host, independent of locale settings, user/group names, timestamps, or file
permissions. Tar archives written by ordinary tooling embed the packer's
username, group name, and current time, which breaks reproducibility. Your job
is to write a packer that normalizes all of that away.

Work in `/app`. A sample tree is shipped at `/app/seed_tree`. **Do not modify
anything under `/app/seed_tree`.** Python 3.12 standard library only; no
network access.

## Deliverables (all three required)

1. `/app/pack.py` — a runnable Python program:
   ```
   python3 /app/pack.py <in_dir> <out_tar> <out_digest>
   ```
   It packs the tree rooted at `<in_dir>` into a reproducible tar archive at
   `<out_tar>` and writes the archive's SHA-256 identity digest to
   `<out_digest>`. It must work on **any** input tree, not just the shipped
   one.

2. `/app/bundle.tar` — the archive produced by running
   ```
   python3 /app/pack.py /app/seed_tree /app/bundle.tar /app/bundle.sha256
   ```

3. `/app/bundle.sha256` — the identity digest file from that same run.

## Packing specification (authoritative)

The verifier compares archive **bytes**, so every rule below matters.

- **Members.** Every directory and every regular file under `<in_dir>`
  (recursively) becomes a tar member. Symlinks and other special files are
  skipped. There must be no duplicates and none missing.
- **Member names.** The member name is the path relative to `<in_dir>` using
  `/` separators and **no leading `./`** (root files are named exactly
  `README.md`, nested ones `docs/spec.txt`, and so on).
- **Ordering.** Members are written in ascending order of the **raw UTF-8 byte
  sequence** of the relative path — plain bytewise comparison. This is
  deliberately *not* locale collation: for example `Zebra.log` (0x5A...) sorts
  before `apple.log` (0x61...), and `Öctet.log` (0xC3 0x96...) sorts after both
  because its first byte is >= 0x80. Do not rely on the shell or on
  locale-aware collation; identical input must yield identical order
  everywhere.
- **Normalized metadata** (identical for every member, regardless of the host):
  - `uid = 0`, `gid = 0`
  - `uname = ""` and `gname = ""` (the owner/group **name fields are empty
    strings** — never populated from the host's `/etc/passwd` or `/etc/group`)
  - `mtime = 0`
  - `mode = 0o755` for directories, `0o644` for regular files (source
    permissions are ignored)
  - directory members have `size = 0`; file members have their true byte size
    followed by exactly those bytes
- **Format.** POSIX ustar (no pax/GNU extensions, so no extra pax headers with
  host-dependent fields). Uncompressed tar (no gzip).
- **Digest file.** `<out_digest>` contains exactly the lowercase hex SHA-256 of
  the produced tar archive bytes, followed by a single newline — nothing else.

## Edge cases the grader probes (hidden trees)

The verifier runs `/app/pack.py` unchanged on hidden trees, so the packer must
be fully general. Hidden probes include:

- names that expose locale coupling: uppercase-before-lowercase
  (`Zebra.log` vs `apple.log` vs `ark.bin`) and non-ASCII UTF-8 names
  (`Öctet.log`, `é.txt`) whose byte order differs from locale collation;
- empty files and empty directories (empty dirs still get a member);
- nested directories several levels deep;
- binary (non-text) file contents passed through exactly;
- mixed-case names where case differences alone decide order.

## Constraints

- Same tree in → byte-identical tar and digest out, every run, any host.
- Do not hard-code the shipped tree's names.
- Do not modify `/app/seed_tree`.
- Standard library only; no network access.
