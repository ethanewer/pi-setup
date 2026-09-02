# silt-barrow — pull one member out of an incident bundle

An incident-response bundle sits at `/app/bundle`. Next to the bundle archive
lives a **large live recorder log** that must never be touched. Your job is to
recover exactly one member of the archive — streamed straight out of it,
**without extracting the archive**.

## What is provided in the environment

* `/app/bundle/incident.tar.gz` — a gzip-compressed tar with several members,
  including:
  - `crash.mkd` — the crash report you need (the wanted member);
  - `hostkeys.pem` — **sensitive**: this key material must never be
    materialized on disk;
  - `recorder.log` — a member that shares its name with the live log beside
    the archive (extracting the archive would clobber it);
  - `snapshot.bin` and `manifest.txt` — not wanted.
* `/app/bundle/recorder.log` — the live recorder log (large). It, and the
  archive itself, must remain byte-identical.

## Deliverables (both required)

### 1. `/app/extract.sh`
An executable script, usable as:

```
bash /app/extract.sh [BASE]
```

with `BASE` defaulting to `/app`. Given any bundle layout of the same shape
(`$BASE/bundle/incident.tar.gz` plus `$BASE/bundle/recorder.log`), it must
write **only** the `crash.mkd` member's exact bytes to `$BASE/out/crash.mkd`
(creating `$BASE/out` if needed). It must stream the wanted member out of the
archive — extracting every member to disk, or leaving **any** other member
(`hostkeys.pem`, `recorder.log`, `snapshot.bin`, `manifest.txt`, …)
materialized anywhere under `$BASE`, is a failure. It must not modify
`incident.tar.gz` or `recorder.log` in any way, and must not read anything
under `/tests`, `/solution`, or `/logs`.

### 2. `/app/out/crash.mkd`
The result of running your script once on the provided bundle:

```
bash /app/extract.sh /app
```

The file must be byte-identical to the `crash.mkd` member inside
`/app/bundle/incident.tar.gz`.

## Constraints / edge cases

- The verifier re-runs `/app/extract.sh` unchanged on hidden bundles with
  different member sets, orders and contents — no hard-coded bytes.
- Do **not** extract the archive into `$BASE/bundle` or anywhere else under
  `$BASE`: besides clobbering the live log, dropping `hostkeys.pem` on disk
  fails the check outright.
- `crash.mkd` may contain long lines and non-ASCII-safe bytes; copy it
  byte-exactly (do not round-trip through text).
- No network access; standard tools only.

## What "done" looks like

1. `bash /app/extract.sh` (or `bash /app/extract.sh /app`) writes
   `/app/out/crash.mkd`.
2. `sha256sum /app/out/crash.mkd` equals the archive member's digest, while
   `/app/bundle/recorder.log` and `/app/bundle/incident.tar.gz` are
   unchanged, and no new files appeared under `/app/bundle`.
