# Harbor Dial — three correct parallel/concurrent executables

You will build **three independent programs** under `/app`. Each one is judged by a
verifier that runs it on hidden inputs you never see, so nothing may be hard-coded
to a single example. Meet the exact APIs, filenames, and formats below. Do **not**
read or import `/tests`, `/solution`, or make network calls. Do not delete or modify
any file that already exists under `/app` other than the five deliverables you create.

There are five deliverables:

| path | what it is |
|---|---|
| `/app/pipeline_parallel.py` | pipeline-parallel forward/backward over simulated ranks (numpy) |
| `/app/parallel_assembly.c` | UPC-style shared-memory assembly over pthreads, builds `/app/pgen` |
| `/app/pgen` | compiled binary produced from `parallel_assembly.c` |
| `/app/rank_*.out` | the per-rank output files produced by running `./pgen` on `/app` |
| `/app/asyncio_pool.py` | a max-concurrency-gated asyncio task scheduler |

The verifier imports `/app/pipeline_parallel.py` and `/app/asyncio_pool.py` and
**executes** `/app/pgen`. All three are required.

---

## Part A — Pipeline-parallel module (`/app/pipeline_parallel.py`)

A pure-Python/numpy implementation of pipeline-parallel execution. Layers `0..L-1`
are owned by pipeline stages, one stage per rank in a simulated world of `R` ranks.
We use `numpy` only.

The module must expose exactly these functions (module importable; keep definitions
at top level, no code that runs only under `if __name__ == "__main__"` required):

```python
def partition(num_layers, num_ranks, rank) -> list[int]
def build(num_layers, num_ranks, rank, dims, seed=0, scale=0.1) -> dict[int, tuple]
def stage_forward(block, x) -> (out, acts)
def forward_all(num_layers, num_ranks, full, x) -> np.ndarray
def backward_all(num_layers, num_ranks, full, x) -> (grads, grad_input)
```

### Semantics (must match exactly)

- **`partition(num_layers, num_ranks, rank)`**: the contiguous, evenly-split slice of
  layer indices owned by `rank`: `lo = num_layers*rank // num_ranks`,
  `hi = num_layers*(rank+1) // num_ranks`; returns `list(range(lo, hi))`. Every layer
  index `0..num_layers-1` is owned by exactly one rank. If `num_ranks > num_layers`,
  some ranks own an **empty** slice (that lives rank simply passes data through).

- **`build(...)`**: `dims` is a list of length `num_layers+1`; `dims[l]` is the input
  width of layer `l` and `dims[l+1]` its output width. Returns a dict mapping each
  owned layer index `l` to `(W, b)` where `W` is `np.ndarray` shape
  `(dims[l], dims[l+1])` and `b` is `np.ndarray` shape `(dims[l+1],)`. **`b` must be
  all-zero** (zero-initialized bias). `W` is drawn deterministically:
  `rng = np.random.RandomState(seed)`; for each `l` in `0..num_layers-1` in order draw
  `W[l] = rng.normal(scale=scale*?...)` — see note below.

  **Determinism / reproducibility requirement:** the per-layer weights for a given
  `(num_layers, dims, seed, scale)` must be **independent of `num_ranks`**. That is,
  `build(N, R1, r, ...)` and `build(N, R2, r, ...)` must hand back the *same* `W` for
  the same layer index. The simplest way: always advance the single `RandomState`
  through all `num_layers` in ascending order and then return the slice this rank
  owns. Use `W[l] = rng.normal(scale=scale, size=(dims[l], dims[l+1]))`. (`scale` is
  the stddev; default 0.1.)

- **`stage_forward(block, x)`**: `block` is this rank's owned layers dict; `x` is the
  incoming activation, `np.ndarray` shape `(batch, dims[first-own-layer])`. Apply each
  owned layer, in ascending layer order: `h = np.tanh(h @ W[l] + b[l])`. Return
  `(out, acts)` where `out` is the final activation (the tensor this rank hands to the
  next rank) and `acts` is a list of intermediate activations. An owned empty block
  returns `(x, [])`.

- **`forward_all(num_layers, num_ranks, full, x)`: full is a model-wide dict of every
  layer `0..num_layers-1 -> (W,b)`. Execute the pipeline: rank 0 receives `x`, runs its
  owned layers, and hands its output to rank 1; and so on. Return the final rank's
  output, shape `(batch, dims[num_layers])`.

- **`backward_all(...)`: loss defined as `loss = 0.5 * np.sum(forward_all(...)**2)`.
  Returns `(grads, grad_input)` where `grads` is a dict `layer_idx -> (gradW, gradB)`
  with `gradW` shape `(dims[l], dims[l+1])`, `gradB` shape `(dims[l+1],)`, and
  `grad_input` is the gradient of the loss w.r.t. the input `x` with shape `(batch, dims[0])`.
  The classic `tanh` chain rule: for layer `l`, `dU = d * (1 - a_l**2)` where `a_l` is
  the layer-`l` activation; `gradW_l = a_{l-1}.T @ dU`, `gradB_l = dU.sum(0)`,
  `d_prev = dU @ W_l.T`. The gradient travels stage by stage (rank-to-rank
  exchange). Any shape errors here are what the verifier catches.

### Edge cases the hidden pipeline cases probe (implement all)
- non-divisible `num_layers` over `num_ranks` (e.g. 7 layers over 3 ranks),
- `num_ranks > num_layers` (empty-owned ranks pass data through),
- `num_ranks == 1`,
- non-uniform `dims`, small `batch`,
- bias must remain exactly zero after `build`,
- gradient array shapes must match `dims`, and `grad_input` must match `x`.

## Part B — Shared-heap assembly (`/app/parallel_assembly.c`, `/app/pgen`)

A UPC-style **shared-memory** assembly written in **C over pthreads**. One shared
integer heap (a single `malloc`'d `long` array with one cell per item in the input
set) is built and filled in parallel by `num_ranks` worker threads, then each thread
writes its **own** per-rank output file. Each thread owns a contiguous slice of the
global item set.

### Command contract
```
/app/pgen <num_ranks> <total_items>
```
- `num_ranks >= 1`, `total_items >= 0`.
- Print the program name in the usage line to standard error and **exit non-zero**
  (`return 2`) on malformed arguments: wrong argument count (anything other than 2),
  or `num_ranks < 1`, or `total_items < 0`. On invalid arguments **no `rank_*.out`
  file** may be written.

### Deterministic per-item value
```
value(i) = (i * 1733 + 17) % 10007        # i is a long
```

### Slices
Rank `r` owns `[lo, hi)` over the global item set:
```
lo = floor(num_ranks * r  /  R)   hi = floor(total_items * (r+1) / R)
```
(as written: `lo = (total_items * r) / R`, `hi = (total_items * (r+1)) / R`, integer
division of non-negative longs). All threads together cover `0..total_items-1` exactly
once.

### Output file per rank
Write a file named exactly `rank_<r>.out` (prefix `rank_`, suffix `.out`, with the
decimal rank id) in the working directory, containing exactly these lines:

```
rank=<r>
lo=<lo>
hi=<hi>
count=<hi-lo>
total=<sum of value(i), i in [lo,hi)>
ok=true
```

Each rank's `total` is the sum of `value(i)` over its own slice, computed after it
stores each of those values into its slice of the shared heap. The binary must also
verify, on exit, that the accumulated **grand total** across all threads equals
`sum(value(i))` over the whole item set; if the check fails it exits non-zero. On
success it exits 0.

The 5 deliverables-printed numbers need no trailing whitespace. The visible example
is `./pgen 3 21` run from `/app` — it must leave `/app/rank_0.out`, `/app/rank_1.out`,
`/app/rank_2.out`.

### Edge cases the hidden verify probes
- a serial `num_ranks == 1`,
- `num_ranks` that does not divide `total_items` evenly,
- malformed argv: no args, `num_ranks=0`, negative `total_items` → each must exit
  non-zero and write nothing.

## Part C — asyncio pool (`/app/asyncio_pool.py`)

An asyncio scheduler for a batch of coroutines constrained by a max-concurrency limit.

Expose (importable module):

```python
class AsyncPool:
    def __init__(self, max_concurrent: int): ...
    async def map(self, coros) -> list: ...

async def run_capped(coros, max_concurrent: int) -> list:
    return await AsyncPool(max_concurrent).map(coros)
```

- `map` runs all coroutines over the same coroutine collection such that **at most
  `max_concurrent` are executing at any instant**, and returns their results in the
  **same order** as the input.
- Use an `asyncio.Semaphore(max_concurrent)` (or an equivalent task pool) internally.
- Cancellation semantics: if the task wrapping the whole batch is canceled, coroutines
  that **had not started** (still waiting to acquire the gate) must **never run**.
- `max_concurrent < 1` should raise `ValueError` at construction.
- An empty input list returns `[]`.
- Do not launch jobs before they can run (i.e. do not pre-wrap coroutines into
  already-scheduled `Task`s outside the gate).

### Edge cases the hidden cases use
- cap smaller than the batch (e.g. caps 3 jobs 8/12),
- cap equal to the batch size,
- an empty input list,
- cancellation mid-batch: only already-started jobs may have started.

---

## Self-check before finishing
- `python3 -c "import pipeline_parallel, numpy"` works.
- `cd /app && ./pgen 3 3` exits 0 and leaves `rank_0.out`, `rank_1.out`, `rank_2.out`.
- `python3 -c "import asyncio_pool"` works.

When done all five deliverable paths under `/app` must be present. Correctness is
decided by the verifier re-running and checking your code — there is nothing to print
to stdout for a reward.