# Consolidator relay: emit dispatch plan records

The **Skerry consolidator** intake relay ingests freight requests as JSONL and
must emit **dispatch plan records** in a strict schema. A downstream service
deserializes the emitted records with a schema-exact parser: any wrong key,
wrong order, wrong JSON type, or non-compact structure breaks it. Your program
is run **by the checker on hidden request files it supplies** — not just on the
provided input — so it must implement the contract below generally.

## Deliverables (all three required)

1. `/app/solve.py` — a runnable Python 3 program (standard library only) with
   this interface:
   ```
   python3 /app/solve.py <requests_jsonl> <out_plans_jsonl> <out_summary_json>
   ```
   It reads the request file and writes the two artifacts described below. It
   must work on **any** request file conforming to the contract.

2. `/app/plans.jsonl` — the plan records your program emits **for the provided
   `/app/requests.jsonl`**:
   ```
   python3 /app/solve.py /app/requests.jsonl /app/plans.jsonl /app/summary.json
   ```

3. `/app/summary.json` — the summary your program emits for the provided input
   (same invocation as above).

## Input format

`requests_jsonl` is UTF-8 text, one request per line. Each line is either a
**valid request** or **invalid** (skipped, but counted):

A valid request is a single JSON object with:
- `id`: a non-empty string,
- `batch`: a non-empty string (the batch id),
- `spec`: a JSON object with:
  - `vessel`: a string,
  - `teu`: a JSON number (int or float) that is **not** a boolean and is `>= 0`,
  - `transit_days`: a JSON integer (not a boolean, no fractional part)
    that is `>= 1`,
  - `priority`: exactly one of the strings `"standard"` or `"expedite"`,
  - `oversize`: an optional boolean; when absent it defaults to `false`.

Everything else makes the line invalid, including: unparseable JSON (e.g.
truncated lines, stray text, `55.` style numbers), non-object JSON (arrays,
numbers, `null`), missing `id`/`batch`/`spec` or any required `spec` field,
empty `id`/`batch` strings, wrong JSON types (string `teu`, float
`transit_days`, boolean `teu`, `"yes"` for `oversize`, uppercase
`"EXPEDITE"`, negative `teu`, `transit_days < 1`). Extra keys anywhere in a
valid request (top level or inside `spec`) are **ignored**. If the same key
appears twice in one JSON object, the standard last-value-wins rule applies.
Blank lines and whitespace-only lines are invalid.

## Output 1: plan records (`<out_plans_jsonl>`)

One record per valid request, **in input order**, each line compact JSON
(separators `,` and `:`, no spaces) ending with a newline:

```json
{"id":"...","batch":"...","shape":{"capacity":<float>,"days":<int>,"code":"<str>","vessel":"<str>"}}
```

- Top-level keys exactly, in order: `id`, `batch`, `shape`.
- `shape` keys exactly, in order: `capacity`, `days`, `code`, `vessel`.
- `capacity` = `round(float(teu), 2)` — a JSON **float** (`120` must be
  emitted as `120.0`, never as the integer `120`).
- `days` = `transit_days` (JSON **integer**).
- `code` = `"EXP"` if `priority` is `"expedite"` else `"STD"`, suffixed with
  `"-X"` when `oversize` is true (`"EXP-X"` / `"STD-X"`).
- `vessel` = the vessel string unchanged.

If there are no valid requests the file is empty (zero bytes). The checkers
parser asserts: every line parses, key lists are exactly as above **in that
order**, `capacity` deserializes as a float (not an int), `days` as an int,
and each line re-serializes byte-identically under compact separators.

## Output 2: summary (`<out_summary_json>`)

A JSON object written with `indent=2` and a single trailing newline, keys
exactly in this order:

```json
{
  "requests": <total lines in the input file>,
  "plans": <number of valid requests>,
  "rejected": <requests - plans>,
  "expedited": <plans whose code starts with "EXP">,
  "batches": {"<batch id>": <plan count>, ...}
}
```

`batches` maps each distinct batch id to its number of emitted plan records,
with keys sorted ascending (plain string sort). All values are integers.
Line counting rule: the file content split on `"\n"`, dropping a single
trailing empty element if the file ends with a newline; an empty file has
zero lines. All summary integers are exact (`rejected = requests - plans`).

## Edge cases the hidden files probe

- Valid requests with extra keys at top level and inside `spec` (ignored).
- Boolean masquerading as a number (`teu: true`), float `transit_days`,
  string `oversize`, uppercase priority, negative `teu`, zero `transit_days`.
- Unparseable lines (truncated JSON, `55.` numbers), non-object JSON
  (`[1,2]`, `null`), duplicate `id` keys (last value wins).
- `teu` given as `0`, `0.004`, and values needing 2-decimal rounding.
- Mixed `oversize`/`expedite` combinations producing all four codes.
- An empty input file (zero lines) and an all-invalid file.
- Duplicate batch ids across non-adjacent lines.

## Constraints

- Standard library only; no network; the program must exit 0.
- The checker runs your program unchanged on hidden request files with fresh
  names and content — do not hard-code the provided file.
- Do **not** modify or rename `/app/requests.jsonl`.
- The program must never read `/tests`, `/solution`, or any checker data.
