# Score telemetry traces with a frozen anomaly model — under a hard memory cap

A furnace fleet ships a frozen anomaly-scoring model. Telemetry arrives as
traces: each trace is a run of sensor windows ("patches"), and a single trace
can contain **hundreds of thousands** of patches. You must write a streaming
scorer that forwards every patch through the model, aggregates per-trace
anomaly scores, and stays inside a strict memory budget and wall-clock
deadline.

## Environment

- Working directory: `/app`. Read-only fixtures (you MUST NOT modify or delete
  them):
  - `/app/model.npz` — the frozen model, numpy arrays with keys:
    `W1` shape `(16, 32)`, `b1` shape `(16,)`, `W2` shape `(1, 16)`,
    `b2` shape `(1,)`.
  - `/app/data/traces_visible.csv` — visible input: header
    `trace_id,x0,...,x31`; 6 traces; 75,000 patch rows total; rows of the same
    trace are contiguous; trace ids are arbitrary tokens (not necessarily
    sorted).
- Python 3.12 with `numpy` and `pandas` is installed. There is **no torch** in
  this image — the model is a plain numpy feed-forward net.

## The model and scoring rule (use it exactly)

For a patch feature vector `x` (32 values):

```
h = relu(x @ W1.T + b1)          # shape (16,)
logit = h @ W2.T + b2            # scalar
p = sigmoid(logit)               # anomaly probability in [0, 1]
```

The **trace score** is the **mean of `p` over all patches of the trace**.
Compute in float64 (the `.npz` arrays are float64; keep them that way).

## Deliverables (both required)

1. `/app/score_traces.py` — a runnable Python program with this interface:
   ```
   python3 /app/score_traces.py <traces.csv> <out.txt>
   ```
2. `/app/trace_scores.txt` — the output your program produces **when run on
   the provided visible input**:
   ```
   python3 /app/score_traces.py /app/data/traces_visible.csv /app/trace_scores.txt
   ```

## Output format

- One line per trace, formatted `%.4f` (e.g. `0.4399`), in **first-occurrence
  order** of `trace_id` in the file.
- The same bytes must go to **stdout** and to `<out.txt>` (no header, no extra
  text).

## Streaming / bounded memory is MANDATORY

- Read the input in chunks (e.g. `pandas.read_csv(..., chunksize=...)`) and
  only keep per-trace running aggregates plus the current chunk in memory.
  Loading a whole trace set into one array/tensor or one full `read_csv` will
  bust the RAM budget.
- The verifier feeds a generated stress set of **1.2 million patches** and
  enforces a hard **peak-RSS cap of 400 MB** (measured on your process) plus a
  wall-clock deadline. Runtime must grow **roughly linearly** in the number of
  patches.

## Error handling (probed by the grader)

The program must write a diagnostic to **stderr** and exit with a **non-zero
status** (never invent scores) when:

- the input header is missing `trace_id` or any of `x0..x31`;
- a feature value is non-numeric or non-finite.

A **header-only** input (zero patch rows) is *not* an error: exit 0 with empty
stdout and an empty output file.

## Edge cases the verifier probes

- A trace set with **thousands of small traces** (do not blow up per-trace
  bookkeeping).
- Trace ids that are arbitrary strings whose first-occurrence order is not
  sorted — output order must follow the file.
- One huge trace covering almost the whole file.
- Unusual but valid chunk boundaries (trace sizes not divisible by any chunk
  size you might pick).

## Constraints

- CPU only; no network access at verify time; numpy/pandas standard stack.
- Do not modify `/app/model.npz` or `/app/data/traces_visible.csv`.
- The verifier re-runs `/app/score_traces.py` unchanged on hidden inputs that
  follow the same format, so do not hard-code to the visible file.
