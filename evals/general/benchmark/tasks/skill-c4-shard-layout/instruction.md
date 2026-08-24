The **C4** (Colossal Clean Crawled Corpus) dataset is stored as gzip-compressed JSON
shards. A standard C4-style corpus has this on-disk layout:

- One file per shard, named `c4-train.<index:05d>-of-<total:05d>.json.gz`, where
  `index` is the zero-based shard number (zero-padded to 5 digits) and `total` is the
  total number of shards the split is organized into (zero-padded to 5 digits; for C4
  train this is 1024).
- Each shard file is gzip-compressed; decompressing it yields one JSON object **per
  line** (`{"text": ..., "url": ...}`).

In `/app/c4` you have 8 such shard files (indices 0–7 of a nominal 1024-shard train
split), each containing 4 records.

Write `/app/c4_analyze.py` that:

1. Scans `/app/c4` for `*.json.gz` files.
2. For each file, parses the **index** and **total** from the shard name, and counts the
   number of records inside by decompressing and counting JSON lines.
3. Writes `/app/c4_summary.json` with exactly these keys/values:

```json
{
  "split": "c4-train",
  "shard_total": 1024,
  "shards_present": 8,
  "records_per_shard": 4,
  "total_records": 32,
  "min_index": 0,
  "max_index": 7,
  "missing_count": 1016
}
```

`shard_total` is the `total` parsed from the filenames, `missing_count` is
`shard_total - shards_present`. The verifier recomputes all of these numbers itself from
the shard files in `/app/c4` and compares them with your JSON.