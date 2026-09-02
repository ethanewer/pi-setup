# larch-dial: drive a fixture tree to green and report it

You are handed a fixture tree that mimics an evolving library's build/rendering
setup and a tiny pytest suite. Your job is to write one **Python program**,
`/app/solve.py`, that processes **any** such fixture tree — the one shipped in
`/app` today, and fresh ones the verifier mounts under `/tests/hidden` — and
writes a deterministic JSON report. This is a general reusable tool, driven
only by command-line arguments; it must not be a one-off for the shipped path.

## Command line (the only inputs)

```
python3 /app/solve.py <FIXTURE> <WEIGHTS> <INPUTS> <OUTPUT>
```

Exactly **four** positional path arguments, in this order:

| arg | meaning |
|---|---|
| `FIXTURE` | directory of the fixture tree (contains `config/`, `suite/`, `cap.txt`) |
| `WEIGHTS` | a JSON file: a flat object `{"family": float_weight, ...}` |
| `INPUTS` | a CSV file of data rows (see below) |
| `OUTPUT` | where the JSON report is written |

Do **not** hard-code any fixture, weight, or input path into the program — every
path comes from `sys.argv`. The program must read a fixture's own config and
data purely from these arguments.

## Dependencies

Use only the **stdlib** plus **`pytest`**. Do not import or rely on any other
third-party package (no numpy, scipy, pandas, etc.). The verifier statically
checks the imports in `solve.py` and rejects anything outside the standard
library.

## The fixture tree

```
<FIXTURE>/
  config/
    main.txt        fixed frame, contains a line reading exactly  @@INCLUDE@@
    synonyms.txt    permitted-synonym map, one `key=value` per line
    incr.txt        subordinate include file to rewrite (the editable part)
  suite/            pytest test files (the focused suite to drive green)
  cap.txt           an integer: the ceiling for the report sequence length
```

### synonyms.txt
Plain text. Each line is a mapping `token=synonym`. Blank lines and lines
starting with `#` (comments) are ignored. Only these `token` values are
**permitted** to be rewritten; every other word in the include must be left
exactly alone.

### Editing `incr.txt` (the include rewrite)
Open `config/incr.txt`, and for **every whitespace-separated token** replace it
with its synonym **iff** the token (stripped of surrounding punctuation such as
`, . ; : ' " ` ( ) ! ? -` — leading and trailing only) equals a key in
`synonyms.txt`. Tokens not in the map are preserved verbatim, including their
punctuation. Keep the line structure of the original include.

Examples (given `rune=glyph`):
- `rune!` → `glyph!`
- `(rune)` → `(glyph)`
- `rune-dash` → `rune-dash` (the dashed whole is not a map key, so unchanged)

Write the result to `config/incr.edited.txt` (this is the **edited include**).

### Rendering `compiled.txt`
Read `config/main.txt` and replace the single line that is exactly `@@INCLUDE@@`
with the **whole edited include text** (the same text you wrote to
`config/incr.edited.txt`). Every other line of `main.txt` is copied through
unchanged. Write the result to `config/compiled.txt`.

### Protected files
`config/main.txt` and `config/synonyms.txt` are **inputs** and must remain
byte-identical to their original contents. The verifier hashes them and fails
you if you modify either.

### The pytest suite (`suite/`)
Drive the suite in `<FIXTURE>/suite` to green: run
`python3 -m pytest --tb=no -q <suite>/suite` (from `<FIXTURE>` as the working
directory) and count how many tests pass. The suite only passes once the
include rewrite and compiled render above are correct (it asserts the synonym
tokens were substituted, the unpermitted tokens were preserved, and the
compiled output inlines the edited include). Record the passing count as
`pass_count` and the process exit code as `suite_exit`.

## Numeric scoring (`fscore`)
Read `INPUTS` as CSV each row having exactly three fields
`family,count,warp` (header row ignored). Skip any row that is blank, has the
wrong field count, or whose `count`/`warp` are not numeric. For each valid row,
`contribution = warp * count * weight[family]` where `weight` comes from the
`WEIGHTS` JSON (families absent from the weights contribute `0.0`). Sum all
contributions and round to 3 decimals. That is `fscore`.

## The report (written to `OUTPUT`)
A JSON object with **exactly** these keys:

```json
{
  "fscore": 32.0,
  "pass_count": 3,
  "sequence": "<64 hex chars>",
  "edited_sha256": "<64 hex chars>",
  "compiled_sha256": "<64 hex chars>",
  "cap": 64,
  "main_sha256": "<64 hex chars>",
  "synonyms_sha256": "<64 hex chars>",
  "suite_exit": 0
}
```

- `fscore` — computed as above (float).
- `pass_count` — number of passing pytest tests (int).
- `sequence` — the sha256 hex digest of the **edited include text** (the exact
  text you also wrote to `config/incr.edited.txt`). This is a compact,
  fixed-length representation of the designed content.
- `edited_sha256` — same digest as `sequence`.
- `compiled_sha256` — sha256 hex digest of the **compiled** text.
- `cap` — the integer read from `<FIXTURE>/cap.txt`.
- `main_sha256` — sha256 hex digest of the (unchanged) `config/main.txt`.
- `synonyms_sha256` — sha256 hex digest of the (unchanged) `config/synonyms.txt`.
- `suite_exit` — pytest process exit code.

### Length ceiling (cap)
`sequence` must be **no longer than** `cap` characters. In these fixtures the
ceiling is set to exactly the length of a sha256 hex digest (64), so the
sequence must be the digest itself; a raw dump of the include would be far too
long and fails. `edited_sha256`/`compiled_sha256`/`main_sha256`/
`synonyms_sha256` are always 64 hex chars. All digests are lowercase hex.

## Constraints the verifier enforces
- **CLI-only config**: solve.py reads everything from its four arguments; no
  hard-coded fixture/data paths, and `sys.argv` is actually used.
- **Dependency constraint**: only stdlib (plus pytest for driving the suite).
- **Source-size cap**: the **gzip-compressed** length (by default
  `gzip.compress`) of `/app/solve.py` must be **≤ 2400 bytes**. Keep the
  implementation compact.
- **Generality**: it must run correctly on fresh hidden fixture trees with
  different directories, synonym maps, include texts (including punctuation
  attached to permitted tokens), weights, and data rows (including blank lines,
  `#` comments, malformed rows, and files with no data rows).

## Deliverables
- `/app/solve.py` — the reusable program (must exist, runnable, within the size
  cap). The verifier executes it again on the visible and on hidden fixtures.
- `/app/answer.json` — the report produced by running
  `python3 /app/solve.py /app/project /app/weights.json /app/inputs.csv /app/answer.json`
  on the shipped fixture.

Note: `/app/project` is only the visible fixture; the verifier mounts entirely
fresh trees, so build the tool around the four-argument contract, not the
shipped paths.
