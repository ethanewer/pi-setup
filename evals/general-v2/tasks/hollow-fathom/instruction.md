# Hollow Fathom — Report Pipeline Provisioning

You are provisioning a small cost-reporting engine for the "hollow fathom"
service. Everything you build lives in `/app`. A verifier will later **execute
every deliverable in a fresh process against its own hidden inputs**, so nothing
may depend on the current shell session — each program must be general and
re-runnable.

Your working directory is `/app`. The container already has `python3` and `jq`
installed. Five deliverables are required, at these exact paths:

- `/app/derive.py`
- `/app/answer.txt`
- `/app/diff_series.py`
- `/app/report.jq`
- `/app/report_args.json`

---

## 1. `/app/derive.py` — derive the service config token from dispersed clues

The upstream team scattered the config-token recipe across a directory of plain
text "clue" files. A solver directory holds:

- one **base file** named exactly `base.txt`, whose first non-blank line is a
  single signed integer (the starting value); and
- zero or more **step files** whose names start with the literal prefix `step_`
  (e.g. `step_a.txt`, `step_build.txt`). Each step file has, in order:
  - line 1: an operator token, one of exactly `add`, `sub`, `mul`, `div`, `mod`;
  - line 2: a single signed integer operand.

Any other file in the directory (any name, e.g. `README.txt`, `notes.log`,
`.gitkeep`) is **not a clue** and must be ignored.

**Derivation rule.** Start with `base`. Then consider only the step files in
**ascending lexicographic order of their filename** (e.g. `step_a.txt` before
`step_b.txt`; a plain string sort of the full filename). For each, apply its
operator to the running value:

- `add O` → value + O
- `sub O` → value − O
- `mul O` → value × O
- `div O` → integer floor division: `value // O` (Python semantics, truncating
  toward minus infinity); O ≥ 1 in every test feed.
- `mod O` → `value % O` (Python semantics); O ≥ 1.

Robustness (the verifier feeds you messy clue directories):
- Tolerate leading/trailing whitespace on any line, and skip blank lines.
- Process only files whose name starts with `step_`. Any file with a different
  name — no matter what it contains — is ignored entirely.
- If a `step_` file does **not** have a valid operator on its first non-blank
  line, or lacks a parseable integer operand, or raises any error, that **one
  file is skipped** (its value is not applied); the rest still run. An
  unrecognized operator token also means "skip this file".
- All step files are processed in filename order; a skipped file simply does
  nothing.

CLI contract:

```
python3 /app/derive.py <cluedir> [outfile]
```

- Print the final integer payload to **stdout** (as a decimal integer, no
  padding).
- If a second argument `outfile` is given (and is not `-`), also write the
  integer followed by a single newline to that path (creating parent
  directories as needed). When no `outfile` is given, write to
  `/app/answer.txt` instead.

`answer.txt` must hold the payload derived from the default clue set at
`/app/clues/`.

The hidden cases are different clue directories (different bases, different
operators, negative bases, malformed/skippable step files, out-of-name step
files). The verifier invokes `derive.py` on each and compares stdout to its own
reference derivation.

## 2. `/app/diff_series.py` — mean per-row difference of two series

Two CSV files each hold a measurement series: a header line `key,value`,
followed by rows `KEY,INTEGER`. The two series are aligned by **key** (not by
row position). For each key present in **both** files, the per-row difference is
(value in file A) − (value in file B). Report the **average of all per-row
differences** for the keys common to both files.

CLI contract:

```
python3 /app/diff_series.py <seriesA.csv> <seriesB.csv> [outfile]
```

- Aligning is by key: build a map key→value for each file.
- Only keys present in **both** files contribute; a key that exists in exactly
  one file is ignored.
- If a key appears more than once in a file, the **last** occurrence wins.
- Tolerate blank lines and any row with fewer than 2 comma-separated fields
  (skip them). A row whose value cell is not an integer is skipped. Header
  detection: a row whose first field is the literal `key` is skipped (treat as
  header). Skip all-row handling defensively.
- If there are no common keys, the average is `0`.

Output formatting:
- `mean = round(total / n, 4)` where `total`/`n` are integer sum and count
  (this is Python's banker's rounding, applied once). If `n == 0` the mean is
  `0.0`.
- Print the number as Python's `str(mean)` (so no trailing zeros are forced:
  `5.0` stays `5.0`, `8.3333` prints as `8.3333`, `0` when empty prints as
  `0.0`).
- If the optional third argument `out` is present (and not `-`), also write the
  value + newline to `out`; otherwise print to **stdout** only.

The hidden cases are different series pairs (offset series, negative values,
misaligned keys, extra keys in one file, duplicated keys, malformed rows, and
the no-common-keys edge). The verifier compares stdout against its own
reference.

## 3. `/app/report.jq` + `/app/report_args.json` — a rerunnable jq report

A feed is a JSON **array of records**, each record being an object with four
fields:

- `id`: a string (unique within the feed);
- `zone`: one of the strings `alpha`, `beta`, `gamma`;
- `prio`: an integer;
- `score`: an integer.

The generated **report** is one output line per retained record,
`id|zone|prio|score` (pipe-separated, no surrounding spaces), emitted in a
specific ordering. The same report must be reproducible later by recombining
the persisted filter file and the persisted arguments metadata and re-executing
`jq` on any feed.

`/app/report.jq` (a jq filter file) must implement, given the feed array on
stdin:

1. **Drop** any record that is not a valid report record: it must have a string
   `id`, a string `zone`, and numeric `prio` and `score`, and must satisfy
   `prio ≥ 0`. Anything else is discarded entirely.
2. **Sort** the remaining records by, in order of precedence:
   1. `zone` rank: `alpha`(0), `beta`(1), `gamma`(2) — any unrecognized zone
      string sorts last (rank 3, strictly after `gamma`);
   2. `prio` ascending;
   3. `score` ascending;
   4. `id` ascending (lexicographic string compare).
3. **Form the report** by emitting `id|zone|prio|score` one per line, in that
   sorted order (for the retained records only).

`/app/report_args.json` is a JSON object recording exactly how to invoke jq so
that re-running reproduces the report byte-for-byte. It must have these keys:

- `"program"`: the absolute path `/app/report.jq`;
- `"options"`: an array of jq command-line flags. Every element **must be
  dash-form** (each string begins with `-`). These options are what make the
  report come out as plain, raw, newline-separated lines (the reference uses
  exactly `["-r"]`).

The verifier's regeneration contract: it reads `report_args.json`, uses
`program` as the filter file, keeps `options` in the recorded order, and runs
`jq <options> -f <program> <feed>`; it expects no extra/custom flags the report
would differ. For it to pass, `options` must be dash-form and exactly reproduce
the reference report's raw-line byte output on each hidden feed.

You may use the default feed at `/app/feed.json` (already in the image) to
sanity-check your filter: with the default options `["-r"]` the lines should be

```
x-4|alpha|0|7
x-2|alpha|1|10
x-6|beta|1|9
x-3|beta|3|5
x-1|gamma|2|40
```

Hidden feeds vary: more zones/records, ties on `prio`, all records dropped
(expected empty report), a record missing a field (dropped), etc.

---

## Final requirements

- Work only under `/app`. Do not read/modify `/tests` or `/solution`.
- All three programs must be self-contained and re-runnable from a fresh
  process; do not rely on state from a previous step.
- Everything must be deterministic; integer math is exact, the average uses the
  rules above, and the report ordering is fully specified.
- End with all five deliverables present at their exact paths, and
  `/app/answer.txt` holding the default-clue payload.