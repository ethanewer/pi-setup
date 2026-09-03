# tl-quartz-partition — systematic test-case generation over a TSL spec

The **Quartz Press** print shop designs its print-engine test plan with the
**Category-Partition Method**: every input dimension is partitioned into
categories of choices, properties and constraints narrow the combinations,
and a **frame** (one test case) selects exactly one choice per category. Your
job is to write the generator CLI that turns a spec + parameters into the
final frame set, and to produce the frame set for the shipped spec.

Skill family: tblite-skill (systematic test-case generation).

## Fixtures already in `/app`

- `/app/specs/printer.tsl` — the visible specification. **Its header comment
  documents the full TSL grammar and the exact generation semantics**; read
  it carefully, it is normative.
- `/app/params.json` — generation parameters for the visible spec:
  ```json
  {"base_choice_strategy": "first", "frame_limit": 0}
  ```

## Deliverables (both under /app)

1. `/app/generate_cases.py` — a **Python 3 stdlib-only** command-line tool:
   ```
   python3 /app/generate_cases.py <spec.tsl> <params.json> <frames.json>
   ```
2. `/app/frames.json` — the frame document your tool writes for
   `/app/specs/printer.tsl` with `/app/params.json`.

## TSL in one page (normative details live in the spec header)

A spec is a sequence of `param` blocks and `constraint` lines. A parameter
holds one or more categories; a category holds an ordered list of choices,
each with **at most one** property: `[default]`, `[single]`, or `[error]`, and
an optional integer value (`choice name := 7`). Constraints are boolean
expressions over atoms `param.cat = choice` and `param.cat in lo..hi`
(inclusive range over the selected choice's integer value; a valueless choice
makes it false), combined with `not`, `and`, `or`, parentheses, and
`if A then B` (≡ `not A or B`; the keyword `if` is optional). `#` starts a
comment. `params.json` validation: `base_choice_strategy` must be `"first"`
or `"default"`; `frame_limit` must be an integer ≥ 0.

## Generation semantics (exact)

- **base(category)**: strategy `"first"` → the first listed choice.
  `"default"` → the `[default]` choice if any, else the first listed.
- **fill(category)** (used for slots a frame does not focus on): the
  category's `[default]` choice if it has one, else **base(category)**.
- **Choice classes**: `[error]` → error; else `[single]` → single; else
  ordinary. A choice equal to base(category) gets no dedicated frame.
- **Property rules**: an `[error]` choice may only be selected in an error
  frame focused on it. A **non-base** `[single]` choice may only be selected
  in a single frame focused on it; a `[single]` choice that is a category's
  base may be selected anywhere.
- **Frame order**: base frame first; then, for each group in order
  `single`, `ordinary`, `error`, iterate parameters → categories → choices
  (spec order), skipping base choices. A dedicated frame fixes its focus
  choice and fills every other category with fill().
- **Repair**: when a candidate frame violates a constraint, keep the focus
  choice fixed and enumerate, over the free categories, every combination of
  permitted choices (a free category may use any of its choices that is not
  `[error]` and not a non-base `[single]`); among the combinations satisfying
  **all** constraints pick the one that (1) changes the fewest free
  categories away from fill(), then (2) has the lexicographically smallest
  tuple of listed-choice positions for the free categories in spec order.
- **Failures**: if the **base frame** cannot be repaired, the whole result is
  `unsatisfiable`. If a dedicated frame cannot be repaired, that frame is
  simply omitted.
- **frame_limit**: if > 0, keep only that many frames (in emitted order) and
  renumber ids; 0 keeps everything. Ids are `"F"` + 1-based index
  zero-padded to width `max(2, digits-of-frame-count)`.

## Output schema (frames.json)

`json.dumps(result, indent=2) + "\n"`, keys in this order:
`status`, `strategy`, `limit`, (`reason` only when unsatisfiable), `frames`.
A frame record: `id`, `type` (`base`|`single`|`ordinary`|`error`), `focus`
(`null` for base, else `{"param":…,"category":…,"choice":…}`), `selections`
(`{"<param>": {"<category>": "<choice>", …}, …}`). Unsatisfiable result:
`"status": "unsatisfiable"`, `"reason": "no valid base frame exists"` (the
exact string), `"frames": []`.

## Exit codes

- `0` — success; frames.json written.
- `1` — TSL parse/validation error, or the spec file is missing/unreadable
  (message on stderr); output file not written. Validation covers the
  structural rules above and constraint references: a constraint naming an
  unknown parameter, category, or choice is a validation error.
- `2` — invalid params.json; output file not written.
- `3` — any other failure (e.g. unwritable output path).

## How the grader probes it

The verifier **recomputes the expected frame document with an independent
implementation** and compares exact JSON (parsed) with your tool's output —
for the visible spec/params and for hidden TSL specs (conflicting
constraints, all-single parameters, an unsatisfiable combination) under
hidden params.json variants (both strategies and a frame-limit cap). It also
requires two consecutive runs on the same input to be **byte-identical**,
requires `/app/frames.json` to equal the visible recompute, and checks the
documented exit codes on malformed specs/params. Hardcoding the visible
frames or ignoring the inputs fails every hidden case. No network, GPU, or
extra packages: Python 3 stdlib only, fully deterministic.