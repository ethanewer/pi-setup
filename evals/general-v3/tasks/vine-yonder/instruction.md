# Orchard Data Platform: operator recovery run

You are an operations engineer joining a partially-broken data platform. The
container already ships a set of mock platform back-ends and several broken
components. Your job is to produce **six deliverables** that restore and prove
each piece works **end-to-end**. The grader re-executes every deliverable (and
runs loaders/queries against hidden variant back-ends), so build each program
to be **general and self-contained**, not a one-off.

## Environment that is already installed

Starts and leaflets the mock stack (do not modify these, but you may start it):
- `python3 /app/servers.py` — one process that binds several listeners:
  - **status page** at `http://127.0.0.1:9000/page`
  - a **dataset hub** rooted at `http://127.0.0.1:9000/hub/<dataset>/...`
  - a **blockchain dev node RPC** rooted at `http://127.0.0.1:9000/rpc`
  - a **broken egress proxy** on `127.0.0.1:8051` that answers every request
    with `502 Bad Gateway` (kept deliberately broken).
- The served status page bytes live at `/app/mockdata/page.html` (what an
  unfiltered fetch of `/page` must match byte-for-byte).
- `/app/puller.py` — the platform's outbound fetch tool:
  `python3 /app/puller.py [URL] -o OUT.html`. It honours an **override file** at
  `/app/override/proxy.txt`: when that file holds a non-blank value, that value
  is used as an http/https proxy for the request. Today the file configures the
  broken proxy on `127.0.0.1:8051`, so every fetch returns the proxy error page
  instead of real content.
- `/app/chain_target.txt` — the account address the platform monitors.
- `/app/spark_job.py` — a ready-to-run Spark workload (see section 4).
- `/app/events/*_events.log` — small logs named `<date>_events.log`.
- `/app/pipeline/` — a chained pipeline broken on purpose (see section 5).
- Python 3.12 with `requests`, `datasets`, `pyarrow`, `pyspark`, `flask`,
  `pandas` and a JRE are installed.

Start the stack locally whenever you need to build/verify outputs:
```
python3 /app/servers.py &     # serves 9000 (and the broken proxy on 8051)
```

The grader starts the stack with fresh mock data before re-running your
deliverables, so your programs must work when the server is newly started, and
they must be meaningful to pass on **other hub/chain datasets served on other
ports** (see each section's "edge cases").

---

## 1) Repair the outbound fetch  → `/app/fix-fetch.sh` and `/app/fetched/page.html`

Produce an executable `bash` script `/app/fix-fetch.sh`. When run it must:

1. Diagnose and **neutralise** the broken egress override (the proxy override at
   `/app/override/proxy.txt` that routes through the broken `8051` proxy), and
2. Re-fetch the real page so `/app/fetched/page.html` is created byte-for-byte
   identical to the served `/page` content.

Contract for `/app/fix-fetch.sh`:
- It is run as root with `bash /app/fix-fetch.sh` from a fresh container **with
  the override file still present**, so it must handle the repair **itself**
  (idempotently).
- After it runs, `/app/override/proxy.txt` must be empty or absent, and
  `/app/fetched/page.html` must exist and match the served bytes.
- You may create `/app/fetched/` inside the script (`mkdir -p`).

*Edge case:* if the script leaves the override active, an refetch routes through
the broken proxy and the content-match check fails; the grader verifies both the
override is neutralised and the page bytes match.

---

## 2) Load the reserved dataset slice  →  `/app/load-dataset.py` and `/app/dataset-report.json`

Produce `/app/load-dataset.py`:

```
python3 /app/load-dataset.py [HUB_URL]
```

Default `HUB_URL` is `http://127.0.0.1:9000/hub/rose-orchard`.

Its job: from the hub dataset, follow the dataset manifest/README to determine
**the correct config identifier** and the **reserved split**, load exactly that
slice, and aggregate a numeric over the reporting **field**. Concretely:

- `GET {HUB_URL}/manifest.json` returns JSON with the release `config`s (each a
  list of its splits), plus `required_config`, `required_split`, `field`, and
  `dataset`. The reserved slice lives at `{HUB_URL}/{required_config}/{required_split}.csv`.
- Read the README (`readme.md`) to confirm which config/split is the reserved
  reporting slice if the manifest is in doubt.

Rules for the aggregation (you must implement exactly):
- Read the CSV for that reserved slice. Find the column whose *header* names the
  `field` (the header row is the first row containing that label, header may
  have whitespace padding; other columns may exist).
- Sum the numeric values in that column. **Blank cells, whitespace-only cells,
  and non-numeric cells are skipped (do not error)**. Blank/trailing lines are
  ignored.
- The count of *numeric* values is `rows`.

Write `/app/dataset-report.json`:
```
{
  "name": "<dataset name from manifest>",
  "config": "<required_config>",
  "split": "<required_split>",
  "field": "<field>",
  "rows": <int>,
  "total": <float or int>
}
```

*Edge cases hidden checks probe:* alternate hub **repos** served on other ports
with different names/configs/splits — your script must read the manifest and
report the right config/split/total; hidden CSVs can contain **non-numeric
cells and blank trailing lines** that must be skipped, and decoy configs/splits
you must **not** sum.

## 3) Query the live node RPC  →  `/app/chain-query.py` and `/app/chain-account.json`

Produce `/app/chain-query.py`:

```
python3 /app/chain-query.py [NODE_URL] [TARGET_ADDR]
```

Defaults: `NODE_URL=http://127.0.0.1:9000/rpc`; `TARGET_ADDR` is read from
`/app/chain_target.txt` when not given (the shipped target address is what the
platform reports).

The dev node exposes:
- `GET /rpc/status` → `{name, version, network, syncing, peers, height}`
- `GET /rpc/block/latest` (or `/rpc/block/<height>`) → a block with `hash`,
  `prevHash`, `number`, `timestamp`, `txCount`, `txs[]`
- `GET /rpc/tx/<txhash>` → the transaction (`hash`, `from`, `to`, `amount`,
  `gasUsed`, `blockNumber`)
- `GET /rpc/account/<addr>` → `{address, balance, nonce}`

Query the node for status, the latest block, a transaction inside that block,
and the account record for the target; persist to `/app/chain-account.json`:
```
{
  "node":     {"name":..., "version":..., "network":..., "syncing":...,
               "peers":..., "height":...},
  "block":    {"number":..., "hash":..., "prevHash":..., "timestamp":...,
               "txCount":...},
  "transaction":{"hash":..., "from":..., "to":..., "amount":..., "gasUsed":...,
               "blockNumber":...},
  "account":  {"address":..., "balance":..., "nonce":...}
}
```
Values must be pulled live from the running node (no hard-coded numbers); they
may be large integers so carry them as JSON strings where the node returns
strings. **Generalise:** the grader runs your script again against a second
dev-node (different network/height/blocks/account) on a different port and
target, so everything in the script must come from the queried node, not be
cached for the visible chain.

## 4. Run Spark to completion (local + standalone cluster)  →  `/app/submit-spark.sh` and `/app/runtimes.txt`

Spark standalone lives inside the installed `pyspark` (no systemd). The
workload `/app/spark_job.py` accepts a data dir argument and prints a
machine-readable summary `DATE_SUMMARY::<date>=<count>;...` after reading every
`<date>_events.log` in it.

Produce `/app/submit-spark.sh` that:
1. Ensures a **Spark standalone master** (`spark://127.0.0.1:7077`, UI
   `http://127.0.0.1:8080`) and **one worker** (UI `127.0.0.1:8081`) are up,
   starting them if needed, and waits until reachable.
2. Runs the job via `spark-submit` in **local mode** (`--master local[2]`) and
   in **standalone-cluster mode** (`--master spark://127.0.0.1:7077`), both on
   `/app/events`, both to completion.
3. Rebuilds a **`/app/runtimes.txt`** file (overwrite, not append) with exactly
   two lines, one per run:
   ```
   LOCAL,<date>,<elapsed_ms>
   CLUSTER,<date>,<elapsed_ms>
   ```
   `<date>` is the date attributed to the events data (derived from the events
   file name), `<elapsed_ms>` the wall-clock duration of that spark-submit (a
   positive integer, machine readable).

Re-run safely: because the grader re-runs it, it must be idempotent: a repeated
run overwrites `runtimes.txt` with the two fresh (local, cluster) durations and
still leaves the UI reachable. Timing should be stable (SPARK_LOCAL_IP must be
`127.0.0.1` to avoid hostname-binding errors).

## 5. Fix the chained pipeline  →  `/app/fix-pipeline.sh` and `/app/pipeline.out`

`/app/pipeline/` contains `stage1.py`, `stage2.py`, `stage3.py` that must run
**in that order**. They import a shared helper module and write to a shared
`generated/` directory — but the module file is only present as a misplaced
`pipeline_helpers.py.example`, and `generated/` **does not exist**. Run the
pipeline is currently impossible.

Produce `/app/fix-pipeline.sh`:
```
bash /app/fix-pipeline.sh [PIPEDIR] [OUTFILE]
```
Defaults: `/app/pipeline` and `/app/pipeline.out`. It must, generically, for the
given pipeline directory:
1. restore a misplaced helper module — a `*.py.example` staging placeholder
   should be materialised to its real `<name>.py` when the real module is still
   missing;
2. create the shared `generated/` (or whatever output directory the stages use)
   if absent;
3. run `stage1` → `stage2` → `stage3` in sequence and capture their stdout (the
   markers printed by the stages) into `OUT`.

Each stage also writes its artifact into `generated/`; the grader checks that
`generated/stage1.txt`, `stage2.txt`, `stage3.txt` all exist after the run and
that the captured output shows the full sequence.

Edge case: the grader applies your script to a **second pipeline directory** with
a different helper-module name (also staged as `*.py.example`) and additional
file; your repair must be driven by what's in the directory, so it must not
hardcode `pipeline_helpers`.

## 6. Run the platform monitor  →  `/app/monitor.log`

Produce a small monitor program (e.g. `/app/run_monitor.py`; any name is fine)
and **run it once yourself** so it writes `/app/monitor.log`. The sampler must:
- run for a **total window of ~60 seconds**,
- take a sample **every ~10 seconds** (so about 6–8 samples),
- write one line per sample: `ts=<unix_epoch_seconds> metric=<int> elapsed=<int>`
  (the metric is any stable numeric you choose).

The grader only validates the log artifact: sample count ≥ 6, first-to-last span
between 50 and 70 s, and every inter-sample gap about 10 s (so a loop that
sleeps ~10 s is expected; do not sleep far too long or too short).

---

## General rules

- Create exactly the deliverables listed, nothing depends on anything in
  `/tests/` (you will never see it). Work only under `/app`.
- Your programs must not depend on this machine's exact visible numbers to be
  attached; everything shown must be read from the live services / manifests /
  events / pipeline directory at run time.
- The server stack and Spark may produce logs; you decide where, but do not
  clobber `/app/puller.py`, `/app/servers.py`, `/app/mock`, `/app/events`,
  the node RPC data, or the shipped broken fixtures you still need to diagnose.
- Deliver both the source programs/scripts and the output artifacts listed in
  the deliverables. Output artifacts that the grader re-runs (page, reports,
  runtimes, pipeline.out) are regenerated, but each stored `/app` deliverable
  must exist when you finish.
- Make everything executable where appropriate (`chmod +x` the `.sh`s). Avoid
  permissions you cannot read as root.

When you are done, you should have run the full fetch→load→query→spark→
pipeline→monitor path once successfully and left the artifacts in place.