# LumenPrint admission planner

The **LumenPrint** micro-farm runs a single print cell fed by an intake queue.
Each intake request (a print job) must either be admitted to the day's run or
declined, and admitted jobs run back-to-back on the one cell. You must write a
Python program `/app/solve.py` that, for a given intake basket, emits the plan
records, the run schedule, and the best achievable profit. The program is run
**by an external checker on other baskets it supplies** — not just on your
input — so it must be written generally and obey the exact contract below.

## Deliverables (the checker executes/reads these)

1. `/app/solve.py` — the planner program (you write it).
2. Emitted by running `/app/solve.py` (no arguments) on the visible basket:
   - `/app/plans.jsonl`
   - `/app/answer.json`
   - `/app/schedule.csv`

Run the program yourself so all three reflect its real behaviour.

## CLI contract

`python3 /app/solve.py [WORKDIR]`

- No argument → `WORKDIR = /app`.
- With one argument → the program reads `<WORKDIR>/input/jobs.csv` and writes
  its three artifacts into `<WORKDIR>` (i.e. `<WORKDIR>/plans.jsonl`, ...).
  The checker invokes the 1-argument form on fresh hidden workdirs it
  constructs and compares the written files; it also invokes the 0-argument
  form and compares `/app/...`. Your program MUST therefore be correct on
  arbitrary new baskets, not just the one in `/app/input`.

## Input format

`<WORKDIR>/input/jobs.csv` — header line exactly:
```
id,batch,volume_cm3,layers,duration,deadline,profit
```
One request per following line:

- `id`, `batch` — strings (unique `id` per row).
- `volume_cm3` — finite decimal (e.g. `12.5`, `20.0`); the job's shape.
- `layers` — positive integer; part of the shape.
- `duration` — positive integer; time units the job occupies the cell.
- `deadline` — positive integer; an admitted job must **finish** at or before
  this time unit.
- `profit` — non-negative integer; earned when the job is admitted.

## Scheduling semantics

- One cell; time starts at 0; admitted jobs run back-to-back in some order
  with **no gaps, no overlap, no preemption**; a job occupying `[s, s+d]`
  finishes at `s+d` and must satisfy `s+d <= deadline`.
- Admit a subset that **maximises total profit** of admitted jobs.
- Tie-break: if several subsets achieve the maximum profit, choose the one
  that **prefers NOT to admit earlier-row jobs** (compare rows top-down; at
  the first row where two optimal subsets differ, the subset not containing
  that row wins).
- The emitted run order for the chosen subset is **earliest-deadline-first**,
  ties broken by input row order.

## Output formats (exact)

1. `/app/plans.jsonl` — one compact JSON object per request, **in input row
   order** (one record per request, admitted or not):
   ```json
   {"id":"J-01","batch":"batch-north","shape":{"volume_cm3":12.5,"layers":40,"duration":3}}
   ```
   Key order is exactly `id`, `batch`, `shape`, and `shape` is exactly
   `volume_cm3`, `layers`, `duration`. `volume_cm3` is the parsed **float**
   of the CSV value (`20` or `20.0` in the CSV → `20.0` in the record);
   `layers` and `duration` are integers. Compact separators (no spaces);
   each line ends with a newline.

2. `/app/answer.json` — the maximum total profit, written as a plain integer
   with **no trailing newline** (e.g. `98`).

3. `/app/schedule.csv` — exact header:
   ```
   id,finish
   ```
   then one row per **admitted** job in run order: the job's `id` and its
   finish time (integer). No extra columns; the file ends with a final
   newline. If nothing is admitted, the file is just the header.

## Edge cases the hidden baskets probe

- **Ties**: several subsets with equal maximum profit → the documented
  tie-break decides.
- **Greedy traps**: taking the highest-profit job first is not optimal.
- **Infeasible jobs** (`duration > deadline`) can never be admitted.
- **Zero-profit jobs**: admitting them never raises profit; the tie-break
  keeps them out when profit ties.
- **Exact fits**: a job with `duration == deadline` (run first).
- **Single-job baskets** and fractional `volume_cm3` values.

## Constraints

- Do NOT modify, rename, delete, or hard-code the input file.
- Standard library only; no network.
- The program must never read `/tests`, `/solution`, or any checker data.
- The program must exit cleanly (status 0) on both the 0- and 1-argument
  forms.
