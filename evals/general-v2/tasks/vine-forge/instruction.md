# vine-forge — observatory event-bag grader

A photon-counting observatory stores each observation run as a **bag** of
pixel patches (one CSV row per patch, 32 features). A tiny fixed neural
scorer (`/app/scorer.npz`) grades every patch, and each bag is summarized by
the **number of positive patches** it contains. Bags can be enormous, so the
grader MUST stream the CSV with bounded memory. You must write the streaming
grader and run it on the shipped bag.

## Working directory

Everything runs from `/app`. Python 3.12 is available as `python3`. The
installed stack is `numpy` and `pandas` (torch is NOT installed); CPU only,
no network. Do not modify any file already shipped in `/app`.

## Shipped fixtures

- `/app/scorer.npz` — the fixed patch scorer, a numpy `.npz` archive with
  exactly four float arrays: `W1` (16×32), `b1` (16,), `W2` (1×16),
  `b2` (1,). The patch logit is
  `z = W2 @ relu(W1 @ x + b1) + b2` where `x` is the 32-feature vector
  `f0..f31` (a patch is **positive iff z > 0**, strictly).
- `/app/data/big_bag.csv` — 8 observation bags, 120,000 patches total,
  header `bag_id,f0,f1,...,f31`. Rows of the same bag are contiguous; bag
  ids are integers.

## Deliverables (both required)

1. `/app/score_bags.py` — a streaming bag grader:
   ```
   python3 /app/score_bags.py <bag.csv> <out.txt>
   ```
   - Reads `<bag.csv>` **in chunks** (e.g. `pandas.read_csv(...,
     chunksize=...)` or an incremental CSV reader). A bag file can hold
     millions of patches; loading the whole file into one array, tensor or
     DataFrame at once will exceed the memory budget and fail grading.
   - Scores every patch with the fixed scorer above and accumulates, per
     bag, the number of positive patches. Only bounded per-bag bookkeeping
     may be kept in memory (one counter per bag).
   - Writes to `<out.txt>` one line per bag, in **first-occurrence order**
     of `bag_id`:
     ```
     <bag_id> <positive_count>
     ```
   - Errors: a malformed bag file (missing feature columns, non-numeric
     feature value) must print an error to stderr and **exit non-zero**
     without writing a bogus output. A header-only file (zero patches) must
     produce an **empty** output file and exit 0.
   - Must work on any bag file in this format — the grader re-runs it on
     unseen bags, so hard-coding the shipped bag is not acceptable.

2. `/app/event_scores.txt` — the output produced by running:
   ```
   python3 /app/score_bags.py /app/data/big_bag.csv /app/event_scores.txt
   ```

## Grading

The grader re-executes `/app/score_bags.py` on the shipped bag and on
smaller hidden bags, comparing your per-bag counts to an independent
recompute of the scorer (exact match required there).

It then generates a **stress bag** (~2,000,000 patches, several bags) and
runs your script under a peak-RSS monitor with:
- a hard memory cap: peak RSS must stay **below 450 MB**
  (a full materialization of the stress bag needs > 500 MB and fails), and
- a wall-clock deadline of **240 seconds** (chunked streaming finishes in
  well under a minute; per-bag counts must still match the independent
  recompute, allowing a tiny tolerance for floating-point tie noise).

## Constraints

- CPU only, single container, no network.
- Keep only bounded per-bag state in memory; never accumulate per-patch
  values across the whole file.
- Write outputs only to the paths given on the command line.
