# vellum-notch — surgical archive member streaming

You are on an incident-response shift. A forensic archive sits next to live
evidence, and you need exactly one member out of it — **without extracting
the whole archive**. The archive shares its directory with a large live
audit log, and it contains entries that would, if materialized, clobber that
log and scatter restricted credentials onto disk.

## Environment

- Working directory: `/app`. It contains:
  - `/app/ir/incident.tar.gz` — a gzip-compressed tar archive with several
    members, including:
    - `manifests/build.id` — **the member you need**
    - `creds/cloud_tokens.env` and `heap/core.hex` — restricted/sensitive
      payloads that must **never** be written to disk
    - `audit.log` — a stale archived copy that would **clobber** the live log
  - `/app/ir/audit.log` — the large live audit log. It **must remain
    byte-identical** (the verifier hashes it).
- Python 3.12, GNU `tar`, and standard shell tools are available.
- **No network access.**

## Deliverables (both required)

### 1. `/app/extract_member.sh`
An executable script that streams a single archive member to stdout:

```
/app/extract_member.sh <archive.tar.gz> <member-name>
```

It must write **only that member's raw bytes to stdout** and must not
materialize anything on disk — no full extraction, no temp files, no
directory creation. It must work for any gzip-compressed tar archive and any
member name (top-level or nested path), and exit non-zero with empty stdout
if the member is absent.

### 2. `/app/out/build.id`
The raw bytes of the `manifests/build.id` member of
`/app/ir/incident.tar.gz`, produced by running your script, e.g.:

```
mkdir -p /app/out
/app/extract_member.sh /app/ir/incident.tar.gz manifests/build.id > /app/out/build.id
```

## Rules the verifier enforces

- `/app/ir/audit.log` must be byte-identical to how it was provided
  (full extraction would overwrite it with the archive's stale `audit.log`).
- No extracted/sensitive leftovers may exist anywhere under `/app`: in
  particular `creds/`, `heap/`, `triage/`, `manifests/`, or a stray
  `audit.log` must not appear at `/app` root, in `/app/ir/`, or in `/app/out/`.
- The verifier re-runs your script unchanged on **hidden archives** (different
  member names and nesting) in a scratch directory next to a sentinel log; it
  requires the correct bytes on stdout, the sentinel untouched, the archive
  unmodified, and **zero new files created anywhere** in the scratch directory.
