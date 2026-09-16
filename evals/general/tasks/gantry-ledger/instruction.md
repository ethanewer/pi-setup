# gantry-ledger: prompt regression eval for a structured-extraction family

You are joining a small extractive-QA project. The team ships a
structured-extraction task family (200 shipment records per set) and iterates
on the extraction prompt against a **deterministic local model**. Two prompt
versions are already on disk, and a previous analysis pass produced a
documented baseline (see `/app/docs/README.md`). The most recent prompt
version fixed the primary metric but introduced a fabrication regression. The
team wants you to build the regression-eval harness the project has been
missing, reproduce the documented trade-off from raw measurements, and ship a
third prompt version that clears the production bar on **both** metrics at
once, with an eval report that proves it.

Read `/app/docs/README.md` first: it defines the metrics, documents the
model's behaviour, and records the baseline numbers you must reproduce.

## Environment

- Python 3.12 with the standard library only. No other packages are needed or
  available; do not try to install any.
- The "model" is a deterministic local module at `/app/model` — a pure
  function with no network access. Use it through its documented interface:
  `model.extract(prompt_text, record_text) -> dict` (keys `date`, `amount`,
  `ref`, `carrier`), plus the constant `model.UNKNOWN`. It is deterministic:
  the same prompt and record always produce the same output, with no hidden
  state.
- `/app/data/records.jsonl` — the shipped 200-record reference set
  (`{"id", "text", "gold"}` per line).
- `/app/prompts/v1.txt` and `/app/prompts/v2.txt` — the two shipped prompt
  versions. Do **not** edit or replace these files, and do not modify
  `/app/data` or `/app/docs`.
- Fresh record sets with the same structure may appear under `/tests/hidden`
  when your work is graded. Everything you build must therefore be driven
  entirely by command-line arguments and file contents, never by the fixed
  shipped paths.

## Metrics (exact definitions)

For a prompt `P` and a record set `R`, scoring compares the model's per-record
output against each record's gold fields:

- `ref_acc` — fraction of records in `R` where the extracted `ref` equals the
  gold `ref`.
- `fabrication_rate` — fraction of records in `R` where the extracted
  `carrier` is a concrete value (anything other than the literal `UNKNOWN`)
  and differs from the gold `carrier`. An extracted `carrier` of exactly
  `UNKNOWN` never counts as a fabrication, even when the gold carrier is a
  real name. Both metrics are fractions in [0, 1]; identical inputs produce
  identical outputs.

## Deliverable 1 — the evaluation harness: `/app/harness.py`

A self-contained Python program with exactly this CLI:

```
python3 /app/harness.py <prompt.txt> <records.jsonl> <out.json>
```

- `<prompt.txt>` — any prompt draft file (must work for all of
  `/app/prompts/*.txt` and any new prompt file under `/app/prompts/`).
- `<records.jsonl>` — any record set in the shipped schema, including sets
  mounted by graders at `/tests/hidden/...` and copies you make under
  `/tmp`.
- `<out.json>` — where the report is written.

The harness must run from any working directory (add `/app` to `sys.path`
itself before importing the model). It reads the prompt text, evaluates every
record in the set with `model.extract`, computes the two metrics exactly as
defined above, and writes `<out.json>` as JSON with exactly these keys:

```json
{
  "prompt": "<the <prompt.txt> path exactly as given>",
  "records": 200,
  "ref_acc": 0.97,
  "fabrication_rate": 0.19
}
```

- `records` is the number of non-blank jsonl lines evaluated.
- `ref_acc` is a float equivalent to `ref_rate` as fractions — write the
  key as `ref_acc` with the value `good_refs / records`.
- Exit status 0 on success; print diagnostics to stdout on failure.

## Documented baseline and the production bar

Your harness must **reproduce the documented trade-off**: run it on the
shipped set for `v1` and `v2`. The reference numbers are:

| prompt | ref_acc (primary) | fabrication_rate (secondary) |
|---|---|---|
| `/app/prompts/v1.txt` | 0.60 | 0.00 |
| `/app/prompts/v2.txt` | 0.97 | 0.19 |

The interesting property of this family is the **trade-off candidates**: the
two shipped versions each clear one of the two halves of the production bar —
`v2` clears the primary (>= 0.95) and fails the secondary (<= 0.03); `v1`
clears the secondary and fails the primary. The documented baseline says a
prompt change that fixes formatting regresses the honesty of the carrier
field, and a change that fixes the carrier regresses formatting. A correct
v3 must clear **both** halves of the bar simultaneously on any comparable
record set.

## Deliverable 2 — the third prompt version: `/app/prompts/v3.txt`

Write a new extraction prompt to `/app/prompts/v3.txt` (plain text; prompt
text only, no program code). It must be a genuine, self-contained prompt for
the extraction task — an instruction in natural language with the JSON output
spec. The bar:

- `ref_rate >= 0.95`
- `fabrication_rate <= 0.03`

on the shipped set, and on fresh comparable record sets. Note that clearing
the bar on the shipped set by hardcoding answers is impossible: the model and
the gold are both read from files, records refer to shipments your prompt
will never see, and the graded sets are fresh. The verifier will re-run
`/app/harness.py` itself on three fresh sets with `v1`, `v2`, and `v3`, so
`/app/prompts/v3.txt` must clear the bar there too.

## Deliverable 3 — the proof: `/app/eval_report.json`

Write a JSON report capturing your shipped-set measurements:

```json
{
  "records": "/app/data/records.jsonl",
  "runs": {
    "v1": {"ref_acc": 0.60, "fabrication_rate": 0.0},
    "v2": {"ref_acc": 0.97, "fabrication_rate": 0.19},
    "v3": {"ref_acc": 0.97, "fabrication_rate": 0.0}
  }
}
```

- `"records"` is the literal path you ran against (the shipped set).
- `runs.v1` / `v2` must be the harness's own measurements for the shipped
  prompts; they must reproduce the documented trade-off (v2 above v1 on
  `ref_acc`, v2 above v1 on `fabrication`).
- `runs.v3` must be the harness's own measurement for your
  `/app/prompts/v3.txt` handed the same set, and must clear the bar on both
  metrics.
- Generate the report by actually running the harness — do not hand-write
  numbers.

## Verification contract

Grading happens like this: `/app/harness.py` is executed directly for each of
`/app/prompts/v1.txt`, `/app/prompts/v2.txt`, `/app/prompts/v3.txt` against
each of the fresh record sets (and the shipped set), the two metrics are
cross-checked by an independent scoring of the same model, and your report
and `v3` must satisfy the documented trade-off reproduction and the declared
bar (including the 2-percentage-point tolerance: `v3.ref_rate` must be within
0.02 of `v2.ref_rate`, and `v3.fabrication_rate` must be within 0.03 of
`v1.fabrication_rate`, in the better direction). Rooms:

- Do not modify `/app/data`, `/app/prompts/v1.txt`, `/app/prompts/v2.txt`,
  or `/app/docs`.
- You may write anything under `/app/prompts/` (adding `v3.txt`), `/tmp`,
  and the three deliverable files.
- The harness must work from any working directory and must never read a
  grader-provided expected file.

Build the harness, reproduce the trade-off, find a `v3` that clears both
sides of the bar, and prove it in `/app/eval_report.json`.