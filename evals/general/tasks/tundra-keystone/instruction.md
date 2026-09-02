# tundra-keystone: correct parallel execution on one CPU node

You are building a single-node parallel-execution harness rooted at `/app`.
Python 3.12 with `numpy` and `torch` is installed. Author THREE programs and
produce TWO output artifacts, all under `/app`, meeting the exact contracts
below. The grading harness RE-INVOKES each program on fresh inputs (other worker
counts, layer counts, widths, batch sizes, job sets, caps, pool sizes) and
independently verifies the results, including the edge cases listed at the end.
Your programs must therefore be parametrisable and rerunnable.

Create exactly these deliverables:

* `/app/pipeline_parallel.py`
* `/app/grad_exchange.npz`   (the pipeline's default output artifact)
* `/app/async_pool.py`
* `/app/async_log.txt`       (the scheduler's default output artifact)
* `/app/mp_entry.py`

---

## 1) Pipeline-parallel partitioning + gradient exchange

`/app/pipeline_parallel.py` must be runnable as:

```
python3 /app/pipeline_parallel.py
        [--world-size R] [--layers L] [--d D] [--batch B] [--out FILE]
```

It models L transformer-style linear layers (each `y = x @ W + b`) split across
R ranks. Flags: R = number of ranks, L = layer count, D = hidden / exchange
width, B = micro-batch size. All are non-negative integers (must tolerate
L < R and L == 0).

Behaviour required:

- PARTITION: assign every layer index in [0, L) to exactly one rank; each
  rank's run of indices is contiguous and increasing; no index appears on more
  than one rank. Any distribution (chunks, round-robin, balanced) is fine as
  long as coverage is exact and per-rank runs are contiguous.
- INIT: every layer's bias vector is ZERO-initialized.
- EXCHANGE: every stage activation and every exchanged gradient buffer carries
  shape [B, D]; each stage's output activation (shape [B, D]) is the next
  stage's input, and each stage's input-gradient buffer (shape [B, D]) is sent
  back to the previous stage (deterministic in-process loopback point-to-point
  tensor movement).
- Write a `numpy.savez` archive to `--out` (default `/app/grad_exchange.npz`)
  containing exactly these keys:
  - `world_size`  (scalar int)  = R
  - `num_layers`  (scalar int)  = L
  - `batch`       (scalar int)  = B
  - `partition`   int matrix `(R, kmax)` with `-1` padding; row r lists the
    layer indices owned by rank r
  - `x0`          float array `(B, D)` = micro-batch input
  - `output`      float array `(B, D)` = final activation after all L layers
  - `bias_sum`    float array `(max(L,1),)` per-layer bias sum (all 0)
  - `weights`     float array `(L, D, D)`; `weights[i]` is layer i's weight
  - `biases`      float array `(L, D)`; `biases[i]` is layer i's bias
  - `act_shapes`  int array `(L, 2)`, each row `[B, D]`
  - `grad_shapes` int array `(L, 2)`, each row `[B, D]`
  (No extra top-level keys are required.)
- Numerical consistency: starting from `x0`, performing
  `x = x @ weights[i] + biases[i]` for `i = 0 .. L-1` (in order) must reproduce
  `output` (an independent re-check applies this same computation from the
  archived arrays). When L == 0, `act_shapes`/`grad_shapes` must be shape
  `(0, 2)` and everything must still save.

With NO arguments the script must write `/app/grad_exchange.npz` for
`R=4, L=8, D=16, B=3`.

---

## 2) — asyncio scheduler: concurrency cap + leak-free cancellation

`/app/async_pool.py` must be runnable as:

```
python3 /app/async_pool.py
        [--jobs N --cap C --trigger T --out FILE]
```

Jobs are N dummy asyncio tasks with short durations (pick any in ~[0.02, 0.6]
seconds; varied ok).

Contract:
- At any instant at most C jobs run (in-flight). Nothing may exceed the cap.
- `--trigger T` means: start up to T jobs (FIFO order, job ids 0,1,2,...) then
  CANCEL the queue: a job that never started must not begin afterward.
  - T <= 0  -> start NOTHING; every job is cancelled.
  - T >= N  -> run ALL jobs to completion; nothing cancelled.
  - 0 < T < N -> first T jobs start and finish; the remaining N-T never start.
  Guarantee: a queued-but-not-started task must never leak into execution
  after cancellation is requested.
- Write a single-JSON snapshot to `--out` (default `/app/async_log.txt`) with
  exactly these keys:
  - `n`                 int = N
  - `cap`               int = C
  - `trigger`           int = T
  - `limit`             int = min(max(T,0), N)
  - `started`           ordered list of job ids that started
  - `completed`         sorted list of ids that finished
  - `never_started`     sorted list of ids that never started (cancelled)
  - `cancelled`         same as `never_started`
  - `max_concurrent`    int = highest concurrent in-flight count (<= C)
  - `all_accounted`     bool = (len(started) + len(never_started) == N)

The default run (`-- no args`) must write `/app/async_log.txt` for N=6, C=3,
T=3 and must report `started == [0,1,2]`, `never_started == [3,4,5]`.

The harness re-runs with fresh (N, C, T) combos including C >= N, T == 0, and
negative T.

---

## 3) — guarded multiprocessing entry point

`/app/mp_entry.py` is a self-contained container entry-point script using
`multiprocessing` to compute `f(v) = v*v + 3` for v in range(12) across a pool
of workers. Constraints:

- The worker function is a top-level picklable function and the main body is
  guarded by `if __name__ == "__main__":`, so importing the module under
  `__mp_main__` during spawn does NOT re-run the program body (no recursive
  re-entry, no duplicate execution, no hang).
- Optional integer argument = pool size (default 4): `python3 /app/mp_entry.py 8`.
- Prints EXACTLY ONE marker line `MP_ENTRY_RUN` then one JSON line:
  `{"ok": true, "results": [3,4,7,12,19,...]}` (12 results).
- `python3 -c "import mp_entry"` does nothing (no output, no pool, no hang).

The harness re-executes it with a different pool size; the marker must still
appear exactly once and results must be correct.

---

## Edge cases the harness probes (your code must handle all)

- pipeline: R > L (empty trailing ranks, no crash, coverage still exact);
  L == 0 (valid archive with `act_shapes`/`grad_shapes` of shape `(0,2)`);
  various D and B.
- scheduler: C > N; T == 0; T < 0 (treat as "start nothing"); T >= N.
- mp: pool size other than the default; import must be side-effect free.

Keep runtimes small (each deliverable under a few seconds) and deterministic
within a single run. You may use numpy and/or torch. Do not install anything;
do not start servers; CPU-only container (no GPU).