# Small linked-data conjunctive query engine

You are asked to write a small query engine and use it to answer a linked-data
query over a triple store. Implement `/app/query.py`, a standalone Python 3
program that evaluates a conjunctive set of graph patterns against a list of
RDF-style triples and writes the matching bindings plus a note on the join
order.

## Inputs (do NOT modify)

The verify-time container provides two files in the directory where the program
is launched:

- `triples.json` — a JSON list of triples. Each triple is an ordered array of
  exactly three strings `["subject", "predicate", "object"]`.
- `query.txt` — one pattern per line. A pattern is three whitespace-separated
  tokens (subject, predicate, object). A token whose first character is `?` is a
  **variable**; otherwise it is a **constant** that must equal the triple value
  exactly. Blank lines are ignored, but every non-empty line has exactly three
  tokens.

## Behavior

A pattern matches a triple when constants that appear in the pattern equal the
corresponding triple value, i.e. the triple can be lined up position-wise with
(pattern, value). A match yields a *partial binding* mapping each variable to the
value in its triple position.

A full **binding** is an assignment of every distinct variable that appears in
`query.txt` to a concrete value such that EVERY pattern is satisfied by at least
one triple, all with those variable values (standard conjunctive / join match).
Return the list of **distinct** full bindings (deduplicated).

Determinism rules (important, the grader requires exact output):

- **join_order**: the distinct variables of `query.txt` in order of first
  appearance when scanning patterns top to bottom, and within a pattern subject,
  predicate, object; joined by a single comma. Example: patterns
  `?p operates ?city` then `?city near ?side` give `join_order = "p,city,side"`.
- **bindings**: order the result rows by values of the variables sorted in
  alphabetical order of their names. Each binding dict contains every distinct
  variable.

## Output

Write JSON to the file `query_result.json` in the launch directory with shape:

```json
{
  "join_order": "p,city,side",
  "bindings": [
    { "p": "ada", "city": "rome", "side": "north" }
  ]
}
```

Produce exactly this shape; `bindings` may be an empty list.

## Contract on new inputs

The program must be a general engine: it will be run in fresh temporary
directories on NEW `triples.json` / `query.txt` inputs, so it must derive
everything from the files at run time. Never embed a result specific to the
provided files. The verifier runs `/app/query.py` with the working directory set
to the directory containing the inputs; the program must write `query_result.json`
into that same working directory.

Specific hidden scenarios to handle correctly:

- A query that matches no triple → `bindings` is an empty list; `join_order`
  still lists every variable in first-occurrence order.
- Variables that appear in the predicate or subject position (not just object).
- A single variable reused across two patterns (self-join): bindings must only
  include rows where both patterns agree on that variable (path/chain queries).
- A variable whose possible values only join through another variable.
- Duplicate matching triples: dedupe.
- A pattern whose three tokens are all constants → if every such constant pattern
  is matched by at least one triple, the single empty binding `{}` is produced;
  otherwise `bindings` is empty.
- Repeated variables with the same value must repeat, not be merged.

## What to deliver

- `/app/query.py` — the real program described above (Python 3, stdlib only).
- Running `cd /app && python3 query.py` produces `/app/query_result.json` for the
  provided inputs.

## Constraints

- Do NOT modify `triples.json` or `query.txt`.
- Standard library only.
- The grader tests *both* the provided files and hidden `triples.json` /
  `query.txt` cases; your answer is graded on the program behavior, not its one
  specific run.