# Score robot-day telemetry bags with a fixed risk model — streaming, bounded memory

A warehouse-robot fleet ships a **fixed** risk model. Every robot-day is a
"bag" of sensor-window patches; you must compute one risk score per bag by
forwarding the frozen model over all of the bag's patches. Bags routinely hold
**tens of thousands of patches** (the hidden stress bag holds hundreds of
thousands), so the scorer must stream the input in bounded-memory chunks and
run in roughly linear time. Everything runs in `/app` on CPU. Python 3.12 with
`torch`, `numpy` and `pandas` is installed.

## Provided files (read-only — do NOT modify or delete them)

- `/app/triage_model.pt` — the frozen model, a `state_dict` of exactly
  `Linear(20 -> 32), ReLU, Linear(32 -> 2)` (parameter naming is free; the
  verifier identifies the Linear layers by shape).
- `/app/data/sensor_bags.csv` — visible bag file: header
  `bag_id,x0,...,x19`, 8 bags, 40,000 patches total. Rows of the same bag are
  contiguous, but bag ids are arbitrary integers in arbitrary (non-monotonic)
  order.

## Deliverables (both required)

1. `/app/bag_mean.py` — the streaming scorer, invoked as:

   ```
   python3 /app/bag_mean.py <bag.csv> <out.txt>
   ```

   Contract:

   - For every patch it computes `P(class = 1)`, i.e. the class-1 probability
     from the softmax of the two logits produced by the frozen model.
   - Per-bag score = the **mean** of `P(class = 1)` over all patches of that
     bag, formatted with exactly four decimals (`"%.4f"`).
   - It emits one score line per bag in **first-occurrence order** of
     `bag_id` — to **stdout** — and writes the **same text** to
     `<out.txt>` (no header, no extra text).
   - **Streaming / bounded memory is mandatory.** Read the bag file in chunks
     (e.g. `pandas.read_csv(..., chunksize=...)`) and materialize only a
     bounded number of patch logits at a time. Loading a whole bag (or the
     whole file) into one array/tensor, or any super-linear computation over a
     bag's patches, will exceed the verifier's peak-RSS cap (~400 MB) or its
     wall-clock deadline and fail.
   - Error handling: if `<bag.csv>` is unreadable, is missing the `bag_id`
     column, is missing any feature column `x0..x19`, or contains a
     non-numeric feature value, print a diagnostic to **stderr** and exit
     non-zero — never invent scores.
   - A header-only bag file (zero patches) is **not** an error: output nothing
     (empty stdout and empty `<out.txt>`) and exit 0.

2. `/app/bag_means.txt` — the output your scorer produces on the visible bag:

   ```
   python3 /app/bag_mean.py /app/data/sensor_bags.csv /app/bag_means.txt
   ```

   (8 lines, one four-decimal score per bag.)

## What the verifier checks

- It re-runs `/app/bag_mean.py` unchanged on the visible bag and on hidden bag
  files with different bag counts and sizes (from single-patch bags up to one
  bag with 60,000+ patches), non-monotonic bag ids, and rows of the same bag
  always contiguous. Scores must match an independent streaming recompute
  through the same frozen model (per-line tolerance 5e-4 to absorb float
  summation order); stdout and the output file must be byte-identical.
- On a large generated stress bag (over a million patches) it additionally
  measures the scorer's **peak resident memory** (must stay <= ~400 MB) and
  **wall-clock time** (must finish well within the deadline), i.e. genuinely
  linear-time, chunked processing.
- Header-only input → empty outputs, exit 0; malformed inputs → exit non-zero.

## Constraints

- CPU only, single container, no network at verify time.
- Do not modify `/app/triage_model.pt` or anything under `/app/data/`.
- Do not hard-code scores: hidden bags are different files; the model must
  actually be forwarded.
