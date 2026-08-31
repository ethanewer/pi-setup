# larch-vane — restore the deployment pipeline's executable bits

The **Larch Vane** coastal field station archives mooring-buoy deployments as
raw sensor logs plus a three-stage reduction pipeline. The archive was copied
off a backup volume and **every script lost its executable bit**, so the
pipeline cannot run as intended. Restore the chain and produce the deployment
report — while leaving the shipped tree listing **byte-for-byte** intact.

## Fixtures already in `/app` (read-only contents)

- `/app/pipeline/ingest.sh` — stage 1: normalizes every `*.log` in a
  recordings directory into a staging directory. **Non-executable.**
- `/app/pipeline/enrich.sh` — stage 2: reduces a staging directory into the
  JSON deployment report. **Non-executable.**
- `/app/pipeline/publish.sh` — the chain entry point:
  ```
  /app/pipeline/publish.sh <recordings-dir> <report-json>
  ```
  It calls the other two stages **directly** (`"$HERE/ingest.sh" ...`), so the
  whole chain only works when every script is executable. **Non-executable.**
- `/app/recordings/` — three visible raw logs (`buoy-a.log`, `buoy-b.log`,
  `jetty-c.log`).
- `/app/tree-listing.txt` — the shipped tree listing of `pipeline/` and
  `recordings/`, exactly the output of:
  ```
  cd /app && find pipeline recordings -type f -printf '%p %s\n' | LC_ALL=C sort
  ```

### Log format (raw recordings)

Each line is either a comment (`#` prefix), blank, or a candidate reading with
exactly three comma-separated fields `station,depth_m,battery`:

- after trimming surrounding spaces/tabs from each field,
- `station` must match `[A-Za-z0-9_-]+` (one or more of letters, digits,
  `_`, `-`),
- `depth_m` and `battery` must match `-?[0-9]+` (an **optional leading `-`**
  only — a leading `+` makes the line malformed),
- lines with any other field count or shape are malformed and are dropped by
  the pipeline (they contribute nothing).

## Your job

1. Make **all three** pipeline scripts executable (`chmod +x`) **without
   changing their contents** (the grader compares bytes against pristine
   copies).
2. Run the chain on the visible recordings to produce the report deliverable:
   ```
   /app/pipeline/publish.sh /app/recordings /app/deployment-report.json
   ```
   (exit 0, prints `PUBLISH_OK`).
3. Leave `/app/tree-listing.txt` **byte-for-byte** as shipped, and do not
   create, delete, rename, or modify **any** file under `/app/pipeline/` or
   `/app/recordings/`. The grader regenerates the listing command above and
   requires it to equal the shipped file byte-for-byte — any extra or changed
   file in those trees fails. Stage scratch output outside those trees (the
   pipeline itself already stages under `/tmp`).

## Deliverables

1. `/app/pipeline/publish.sh` — the (executable, byte-identical) chain entry
   point, runnable directly.
2. `/app/deployment-report.json` — the visible-run report, exactly what
   `publish.sh` writes for `/app/recordings`.

## How the grader probes it

- Re-runs `/app/pipeline/publish.sh <dir> <out>` on the visible recordings
  **and on hidden recording directories** you have not seen (valid rows,
  negative depths, trimmed spacing, comments, blank lines, malformed lines,
  files with zero valid rows, an empty file), then independently recomputes
  the report from the raw logs under the format rules above and compares.
- Requires the report deliverable to equal its own visible recompute.
- Requires all three scripts to carry the executable bit and be byte-identical
  to the shipped originals.
- Regenerates the tree listing and compares it byte-for-byte with
  `/app/tree-listing.txt`.

Do not modify the pipeline scripts' contents, and do not touch anything
outside `/app` except `/tmp` scratch. No network is involved.
