# wale-haven: attribute meter readings to monitoring periods

You are the data analyst for **Haven Grid**, a regional utility. The billing
office needs one number per monitoring period: the total kWh the fleet
recorded during that period. The operational context lives in `/app/spec.md`;
the visible dataset is `/app/periods.json` (the schedule) and `/app/events.csv`
(the readings log). Read the specification carefully — it is the contract for
the numbers.

Your job is three deliverables:

1. `/app/aggregate.py` — one self-contained Python 3 program (standard library
   only, no third-party packages) that computes period totals for **any**
   dataset shaped like the visible one, driven purely by command-line
   arguments.
2. `/app/result.json` — the output your program produces when you run it on the
   visible dataset.
3. `/app/decisions.md` — a Markdown document recording the interpretation
   decisions you made while reading the specification (see "Decision log").

## Command line (the only inputs)

```
python3 /app/aggregate.py <PERIODS.json> <EVENTS.csv> <OUTPUT.json>
```

Exactly three positional path arguments, in order: the periods file, the events
file, the output file. The program must read everything from these arguments —
**no hard-coded paths, no constants copied out of the visible files, no
knowledge of the shipped file contents**. The verifier will run your program
against fresh datasets in `/tests/hidden` that it mounts at release time; if the
program special-cases the visible data, it fails there.

Exit code `0` on success, non-zero (with a message on stderr) on failure.

## Input schemas

`PERIODS.json` — a JSON object with a `periods` array. Each element is an
object with exactly `id`, `from`, `to` (strings). Times are naive UTC
`YYYY-MM-DDTHH:MM:SS` (e.g. `2024-06-01T08:00:00`). Periods are consecutive and
non-overlapping: each period's `to` equals the next period's `from`.

`EVENTS.csv` — a header row `timestamp,value` followed by one row per reading.
`timestamp` is the same time format, `value` is a decimal number (kWh).
Datasets are guaranteed well-formed: no blank rows, no missing fields, no
readings outside the overall monitoring span. Timestamps may appear in any
order.

## Output contract

`OUTPUT.json` must be a single JSON object mapping each period `id` to the
period's total:

- **every** period id from the schedule appears as a key — including periods
  whose total is zero, which must appear with value `0`;
- no other keys;
- each value is the exact sum of the `value` fields of the readings attributed
  to that period — no rounding, no truncation, no scaling (a JSON number; `5`
  and `5.0` are equivalent).

## What the specification does not say

`/app/spec.md` is precise about formats and guarantees but silent on at least
one point that materially changes the totals, and the visible data exercises
that point (the file even contains readings recorded to the exact second). Any
defensible resolution is acceptable **provided** you pick exactly one, apply it
uniformly to the visible dataset and to every dataset the verifier runs, and
document it. Do not guess at a "hidden intended answer": the verifier accepts
either standard convention as long as the implementation is self-consistent
and the document matches the code. An inconsistent implementation (a rule that
changes between datasets, readings counted twice, or readings dropped) scores
`0` even with a perfect decisions file.

## Decision log

`/app/decisions.md` (Markdown) must, for every point where you had to make a
judgement call that affects the numbers:

- **name the ambiguity** you found in the specification and where it shows up
  in the data;
- **state clearly the convention you implemented** — name it in words or
  notation a reviewer can match against your program (one or two sentences,
  placed so it is unambiguous);
- **give your reasoning** for that choice and note what would change under the
  alternative.

The verifier reads this file. It checks that the convention you state is in
fact the one your program applies, on the visible dataset and on the hidden
ones. Aim for roughly 150–600 words; a stub will not pass.

## Constraints

- Use the standard library only (`csv`, `datetime`, `json`, and friends — no
  numpy, pandas, or anything else that is not stdlib).
- Do not modify `/app/spec.md`, `/app/periods.json` or `/app/events.csv`; the
  verifier confirms they are byte-identical to the shipped originals.
- The program must be general: fresh hidden datasets differ in the number of
  periods, the boundary instants, the date span and the data volume. Write the
  tool against the argument contract above, not against the shipped files.

## Recall

- `/app/aggregate.py` — the reusable CLI (executed by the verifier)
- `/app/result.json` — its output on the visible dataset
- `/app/decisions.md` — your documented convention choice