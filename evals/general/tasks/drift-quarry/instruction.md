# Drift Quarry — fetch the Cirque avalanche dataset

**Drift Quarry** keeps its avalanche-observation training data as parquet
split files in an S3-style object store. You must write a dataset fetcher that
downloads every object, verifies integrity and schema, and assembles the
train/val/test splits locally.

## Environment

- Working directory: `/app`.
- A loopback-only **Cirque object store** is reachable **right now**:
  - S3-style object endpoint: `http://127.0.0.1:9000` (anonymous HTTP GET, no
    signing). Objects are fetched as `GET /<bucket>/<key>`; a manifest lives
    at `GET /cirque/manifest.json`.
  - The served bucket is **`cirque`**; its data lives read-only under
    `/app/realm`. Do **not** modify `/app/realm`, `/app/object_server.py`, or
    `/app/entrypoint.sh`.
- Installed libraries: `requests` (optional), `pandas`, `pyarrow`, plus the
  Python standard library. No other network access is needed or allowed.
- Python 3.12 is available as `python3`.

### Manifest format (`GET {endpoint}/{bucket}/manifest.json`)

```json
{
  "dataset": "cirque-avalanche-2024",
  "version": "4",
  "columns": ["site", "observed_at", "depth_cm", "wind_kph", "danger"],
  "splits": [
    {"role": "train", "files": [{"key": "train/part-000.parquet",
                                  "sha256": "<hex digest>"}]},
    {"role": "val",   "files": [ ... ]},
    {"role": "test",  "files": [ ... ]}
  ]
}
```

- `columns` is the exact, ordered parquet column name list for **every**
  object.
- Each `files[].key` is a bucket key; `sha256` is the hex SHA-256 of that
  object's bytes.

## Deliverables (both required)

1. `/app/fetch_dataset.py` — a runnable Python program:
   ```
   python3 /app/fetch_dataset.py --endpoint <url> --bucket <name> --out <dir>
   ```
   All three flags are required (missing flag → error, non-zero exit). It must
   work on **any** conforming store (the verifier re-runs it against fresh
   hidden stores on different endpoints/buckets).

2. `/app/dataset/` — the local copy produced by running your program on the
   shipped store:
   ```
   python3 /app/fetch_dataset.py --endpoint http://127.0.0.1:9000 \
       --bucket cirque --out /app/dataset
   ```

## Required behaviour

For every manifest split, in manifest order, and every file within it:

1. Download the object `GET {endpoint}/{bucket}/{key}` to `<out>/<key>`
   (creating subdirectories as needed).
2. Verify its SHA-256 equals the manifest value. On mismatch write
   `<out>/report.json` with `"sha_ok": false` and an error string beginning
   `sha-mismatch:<key>`, print a clear error, and **exit non-zero**.
3. Open it with `pandas.read_parquet` and check that its columns equal
   `manifest["columns"]` (same names in the same order). On mismatch write
   `<out>/report.json` with `"schema_ok": false` and an error string beginning
   `schema-mismatch:<key>`, print a clear error, and **exit non-zero**.

Then concatenate the objects of each role **in manifest order** into
`<out>/<role>.parquet` (only for roles that have at least one file) and write
`<out>/report.json` with **exactly** these keys:

```json
{
  "dataset": "...", "version": "...",
  "columns": ["site", "observed_at", "depth_cm", "wind_kph", "danger"],
  "files_downloaded": 7,
  "total_rows": 512,
  "rows": {"train": 300, "val": 100, "test": 112},
  "splits_complete": {"train": true, "val": true, "test": true},
  "sha_ok": true, "schema_ok": true, "error": null
}
```

- `files_downloaded` = number of objects across all splits;
  `rows[role]` = total rows concatenated for that role; `total_rows` = their
  sum. `splits_complete[role]` = that role has at least one file.
- A manifest with **no `train` or no `test` split** (a split-availability
  failure) is an error: report error string `missing-split:<role>` and exit
  non-zero. A missing `val` is **not** an error (`splits_complete.val` is
  simply `false`).
- If the manifest itself is unreachable, not valid JSON, or missing the
  required fields (`dataset`, `version`, `columns`, `splits`), print a clear
  error mentioning `manifest` and exit non-zero.
- On full success print one summary line
  `FETCH_OK files=<N> rows=<total>` and exit 0.

Failure reports must still be valid JSON with the same keys (`rows` counting
only what was processed so far; unprocessed roles counted as 0 with
`splits_complete[role]` computed from the manifest).

## Edge cases the verifier probes

- a fresh store with a **different dataset, columns and row counts**;
- a manifest with **no `val` split** (must succeed, `splits_complete.val`
  false);
- an object whose bytes **do not match** its manifest digest (must fail with
  `sha-mismatch:<key>` and exit non-zero);
- an object whose parquet **column order differs** from the manifest (must
  fail with `schema-mismatch:<key>` and exit non-zero);
- a bucket with **no manifest at all** (must fail, mentioning `manifest`);
- multi-part splits concatenated strictly in manifest order.

## Hard constraints

- Work only under `/app` (plus the `--out` directory). Never read `/tests` or
  `/solution`.
- Be honest: integrity/schema failures are reported and non-zero, never
  faked. No hard-coding of the shipped dataset names, columns or digests.
- Deterministic; standard library + pandas/pyarrow (+ requests if you like).
