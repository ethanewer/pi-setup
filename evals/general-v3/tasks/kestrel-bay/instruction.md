# Kestrel Bay tide-gauge network — distributed least-squares fit

The **Kestrel Bay sensor network** fits a line to tide-gauge readings by
splitting the work across several worker processes that coordinate through a
CPU **gloo** process group. You must implement the distributed fit program.
You work in `/app`. The fixture `/app/data/tide_gauge.csv` is already on disk.
**Do not modify** anything under `/app/data/`, and never read or touch anything
under `/tests` or `/solution`. The program is re-run on **hidden** datasets
with **hidden worker counts** at verify time, so it must be fully generic.

`torch` (CPU) is pre-installed.

## Data

CSV with header `x,y` and numeric rows. Rows are processed in file order;
**row `i` (0-based) belongs to rank `i % N`** where `N` is the worker count
(round-robin sharding). Some ranks may receive **zero** rows; they must still
join the process group and produce their artifacts.

## Deliverable

**`/app/dtrain.py`** — run as:

```
python3 /app/dtrain.py --data <csv> --out <outdir> --procs <N>
```

- It must **spawn N worker processes** (e.g. via `torch.multiprocessing.spawn`
  or equivalent; guard so spawned children do not re-enter the launcher) and
  join a **gloo** process group (`torch.distributed.init_process_group` with
  `backend="gloo"`) — one rank per worker, world size `N`.
- Each rank `r`:
  1. loads **only its own shard** (rows with `i % N == r`, in file order) from
     the CSV;
  2. moves the shard into **CPU torch tensors of dtype float32** (explicit
     device/dtype movement from the raw parsed values);
  3. computes its local sufficient statistics for least squares —
     `n` (row count), `Σx`, `Σy`, `Σx²`, `Σxy` — and **all-reduces them with
     `SUM`** across ranks (collect them into a single tensor so one
     `all_reduce` call carries all five);
  4. writes `<out>/rank<r>.marker` — a JSON object with exactly these keys:
     `{"rank": <int>, "world_size": <int>, "backend": <str>,
       "local_n": <int>}` where `backend` is the string reported by
     `torch.distributed.get_backend()` and `local_n` is that rank's own shard
     size (0 allowed). Every rank writes its own marker file — markers prove
     real worker processes ran.
- Rank 0 additionally writes `<out>/fit.json` — a JSON object:

  ```json
  {"slope": <float>, "intercept": <float>, "n": <int>,
   "world_size": <int>, "backend": "<str>"}
  ```

  computed from the **all-reduced** global statistics with ordinary
  least squares:
  - `slope = (n·Σxy − Σx·Σy) / (n·Σx² − (Σx)²)`
  - `intercept = (Σy − slope·Σx) / n`

  (`n > 0` is guaranteed for the whole dataset.)

- Create `<outdir>` (and parents) if missing.

## You must also run the visible case

```
python3 /app/dtrain.py --data /app/data/tide_gauge.csv --out /app/output --procs 4
```

so that `/app/output/fit.json` and `/app/output/rank0..rank3.marker` exist
with real content.

## Edge cases the grader probes (hidden runs)

- Different `--procs` values (e.g. 3, 5, and a case with **more workers than
  rows**, so at least one rank has `local_n == 0` but must still write its
  marker and participate in the all-reduce).
- `fit.json` values must match an independent serial least-squares
  computation on the full dataset (small numeric tolerance), with the correct
  `n` and `world_size`.
- Every marker must report `backend` `"gloo"`, the correct `world_size`, and
  the exact round-robin `local_n` for its rank.
- Deterministic behavior; the rendezvous must not depend on pre-existing
  state (use a fresh file/tcp rendezvous per run).

## Constraints

- CPU only; `gloo` backend (not `nccl`, not `mpi`).
- No network access beyond localhost loopback for the process group.
- Do not hard-code the visible dataset, row count, or worker count.
