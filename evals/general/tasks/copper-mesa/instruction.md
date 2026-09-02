# Copper-mesa — pick the top model off a sharded leaderboard

The **Copper-mesa** eval farm stores every model's benchmark run as a shard of
JSON files. You must write a small, fully general picker that scans a results
directory, computes each model's mean score across its tasks, and reports the
**top model's `org/model` identifier as a single trimmed line**. The picker is
re-run by the grader on unseen datasets, so it must follow the rules below
exactly — not just work on the shipped data.

Everything lives in `/app`:

- `/app/data/results/` — the shipped visible dataset (do **not** modify
  anything under `/app/data`).
- `python3` is available (standard library only; no network).

## Results dataset format

A results directory contains **one sub-directory per model run** (any slug
name), plus possibly stray non-directory entries that must be ignored. Each
model directory contains:

- `meta.json` — a JSON object; the model identifier is its `"model"` field
  (a string). The identifier may be padded with surrounding whitespace, which
  must be **trimmed**. If `meta.json` is missing, unparseable, not an object,
  or its `"model"` field is missing / not a non-empty string, the whole model
  directory is skipped.
- one or more `<task>.json` shard files — JSON objects whose `"score"` field
  holds that model's score on the task named by the file name (without
  `.json`). A shard's score counts only if it is a **finite JSON number**
  (`int` or `float`). It must be ignored when it is `null`, a string (even a
  numeric-looking one like `"0.91"`), a **boolean** (`true`/`false` are not
  scores), not finite (`NaN`/`Infinity`), or when the shard file is
  unparseable. Any other keys in a shard are irrelevant. `meta.json` itself is
  never a task shard.

### Averaging and merging rules

- A model's **mean** is the arithmetic mean over all of its counted numeric
  shard scores (from all its directories).
- If the **same trimmed identifier** appears in more than one model directory,
  those directories belong to the same model: **merge** all their counted
  scores into one list before averaging.
- A model with zero counted scores is excluded entirely.
- The winner is the model with the **highest mean** (compare means rounded to
  9 decimal places); on a tie, the **lexicographically smallest** identifier
  wins.
- Scores of different models may live on different scales (0–1 or 0–100);
  average them as plain numbers — never rescale.

## Deliverables (both required)

1. **`/app/pick_top.py`** — a runnable program:
   ```
   python3 /app/pick_top.py <results_dir> <out_file>
   ```
   It scans `<results_dir>` per the rules above and writes the winner's
   identifier as the **only non-whitespace content** of `<out_file>`: a single
   trimmed line (a trailing newline is fine; no extra spaces, no extra lines).
   If no model has any counted score, print `ERR: no scores` to stderr and
   exit non-zero without writing the output file.

2. **`/app/leaderboard_top.txt`** — the output of your program on the shipped
   visible dataset:
   ```
   python3 /app/pick_top.py /app/data/results /app/leaderboard_top.txt
   ```
   Keep the file in place after generating it.

## What the verifier requires

The verifier re-runs `/app/pick_top.py` on the visible dataset and on several
**hidden** datasets with different models, tasks, scales, and trap
combinations, and compares the produced line (trimmed) to the reference
winner. Hidden datasets probe, among other things:

- an exact **mean tie** at the top (lexicographic tie-break),
- a decisive **duplicate-identifier merge** across directories (without the
  merge a different model would wrongly win),
- **whitespace-padded** identifiers,
- boolean / string / `null` / `NaN` / non-finite / malformed-shard traps,
- a dataset where only one model has any counted scores.

It also re-runs the exact Deliverable 2 command and requires
`/app/leaderboard_top.txt` to match the fresh output, and that nothing under
`/app/data` was modified.

## Constraints

- Deterministic; no network; standard library only.
- Do not hard-code the visible dataset's model names or winner.
