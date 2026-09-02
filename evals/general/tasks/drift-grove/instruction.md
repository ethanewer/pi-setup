# Grove Engine — Drift-Grove synthesis bench

You are working on the **Grove Engine**, a camera-calibration pipeline for a fleet of
survey drones. The build chain is failing because six hand-authored components are
missing or broken. Your job is to **author and run** each component so the plant can
ship. Everything runs as plain Python 3.12 in `/app`; `numpy` is installed but optional.

All six components ship as small command-line tools that you **write**, and you also
run them against shipped fixture inputs to **produce the required output artifacts**.
Your tools will be re-run by the plant on fresh input files (including edge and
adversarial cases), so every tool must work from any input file given as a path, on
any directory, inside `/app`.

Do not modify anything under `/app/fixtures/` or `/app/bin/` — those are the plant's
fixtures and fixed instruments.

---

## Workflow

1. Write the six tools in `/app` (exact paths below).
2. Run each tool on its shipped fixture (in `/app/fixtures/`) to create the output
   artifacts listed below (exact paths below).
3. Verify your artifacts yourself against the documented contracts.

Deliverables (all must exist at final paths):

| # | Tool (you write)        | Artifact(s) (you produce)                      |
|---|--------------------------|------------------------------------------------|
| 1 | `/app/search.py`         | `/app/tile-solution.json`                      |
| 2 | `/app/expr.py`           | `/app/expr.txt`                                |
| 3 | `/app/oracle-debug.py`   | `/app/lines.txt`, `/app/probe-log.json`        |
| 4 | `/app/gen-gate.py`       | `/app/gate.def`                                |
| 5 | `/app/gen-table.py`      | `/app/table.csv`                               |
| 6 | (none — tiny source)     | `/app/tiny-source.py`, `/app/compressed-sizes.json` |

---

## Part 1 — sliding-tile searcher (`/app/search.py`)

A 3x3 sliding-tile board: cells hold tile labels `1..8` and `0` for the empty cell.
A move slides exactly one tile into the adjacent empty cell.

**Contract**
```
python3 /app/search.py <puzzle.json> [out.json]      # out defaults to /app/tile-solution.json
```
`puzzle.json`:
```json
{ "board": [5,1,2, 8,0,6, 4,3,7], "goal": [1,2,3, 4,5,6, 7,8,0] }
```
Write a JSON report to `out.json` with this exact schema:
```json
{
  "solved": true,
  "start": [9 ints], "goal": [9 ints],
  "card": 181440, "depth": 10,
  "layers": [ [ [9 ints], ... ], ... ],
  "chain": [ [9 ints], ... ],
  "frontier_disjoint": true
}
```
Semantics the plant checks:
- **`layers`** = BFS *by depth* from `start`: `layers[0]` is exactly `[start]` and
  `layers[d]` is exactly the set of states whose shortest distance from `start` is `d`
  (order within a layer is irrelevant). The layers must be **disjoint** and their
  union must be **every reachable state**.
- **`card`** = number of reachable states; **`depth`** = the largest settled layer
  index (max shortest distance).
- **`chain`** = a shortest board-state walk from `start` to `goal`: each consecutive
  pair differs by one legal tile slide, `chain[0] == start`, and if the goal is
  reachable, `chain[-1] == goal`.
- **`solved`** = whether `goal` is reachable from `start`.
- Edge case: `board == goal` is legal → `solved: true`, `layers = [[start]]`,
  `chain = [start]`, `card = 1`, `depth = 0`.

Your `search.py` must produce these results by **doing a real BFS** — the plant
independently recomputes the distance layers, disjointness, cardinality, and chain
length for your input, and every value must match exactly.

## Part 2 — exact-target expression synthesizer (`/app/expr.py`)

Given a multiset of numbers and an integer target, build an expression that evaluates
**exactly** (rational arithmetic, no floats) to the target.

**Contract**
```
python3 /app/expr.py <spec.json>        # prints the expression to stdout
```
`spec.json`: `{ "nums": [100, 4, 2, 5, 8, 0], "target": 0 }` — any length >= 1.

Rules:
- Use **each number in `nums` exactly once**; no other constants.
- Allowed operators only: `+ - * /`; any parenthesization.
- Division by zero anywhere in the expression is invalid.
- Result must equal `target` exactly under rational arithmetic (e.g. `8/(3-8/3) == 24`).
- The plant parses and evaluates your expression with exact rationals, checks the
  multiset of numeric constants equals `nums`, and checks the value equals `target`.
- Every input the plant supplies is **guaranteed solvable**.

Produce `/app/expr.txt` by running your tool on `/app/fixtures/expr_spec.json` (4
numbers, target unreachable by reckless float math — use exact rational search).

## Part 3 — drift-log debugger (`/app/oracle-debug.py`)

Grove collects a **drift log** whose length is unknown. It is not readable as a file:
the only way in is a probing instrument, `/app/bin/observe`, which exposes the log
through exactly **two control endpoints**:

```
/app/bin/observe <ctx> span <k>     # prints 1 if log position k exists (0 <= k < L), else 0
/app/bin/observe <ctx> leaf <k>     # prints the log entry at position k, or -EOF if k >= L
```
`<ctx>` is a small context file (shipped: `/app/fixtures/oracle_ctx.json`; the plant
will point you at hidden context files with **different** log lengths). The length `L`
is a derived property of the context, **not** its byte/line count — only the oracle
can tell you whether a position exists.

**Contract**
```
python3 /app/oracle-debug.py <ctx>
```
- Use `span` to locate `L` — it is a monotone predicate (positions `0..L-1` exist,
  everything after does not), so exponential bracketing plus binary search works.
  The log is at most 2000 entries, but you are on a **strict call budget of 40
  probes total**; a naive linear scan over 2000 positions blows the budget.
- Use `leaf` to confirm the boundary (position `L` must return `-EOF`).
- Write `/app/lines.txt` containing **only the detected line count** (a single
  integer, newline-terminated).
- Write `/app/probe-log.json` — your debugging transcript:
  ```json
  { "answer": 552, "calls": 22, "budget": 40,
    "problem": "drift-log-length",
    "probes": [ {"endpoint": "span", "k": 2048, "reply": "0", "kind": "size"}, ... ] }
  ```
  `probes` must include **both** endpoints (`span` and `leaf`), every probe you made,
  and `calls` = number of probes must be ≤ `budget`.

## Part 4 — gate generator (`/app/gen-gate.py`)

Grove's pipeline needs a pure combinational gate network. The shipped simulator
`/app/bin/sim-gates` evaluates a netlist and **rejects any net whose total line count
exceeds the processing bound of 32000 lines** (it prints `EXPANDED` and exits 1).

Netlist format (`/app/sim-gates <net.def> <bits.txt>`):
```
INPUTS n                      # first line: number of input bits
g0 XOR a b                    # wires: integer input bit 0..n-1, or g<j> (earlier gate)
...
OUT <wire>                    # final wire, result of the whole net
```
- `bits.txt` is exactly `n` characters of `0`/`1` on one line.
- Gates evaluate in order; only `XOR`/`AND`/`OR` are legal ops; dangling wire
  references, wrong bit width, and parse errors are rejected.
- The simulator counts **every non-empty line** of the net against the 32000 cap
  *before* evaluating.

**Contract**
```
python3 /app/gen-gate.py <nbits> <out.def> [maxlines=32000]
```
- Generate a net that computes **the XOR of all `nbits` input bits** and nothing
  else, written to `<out.def>`.
- The total line count of `<out.def>` must be ≤ `maxlines`.
- If the input is **impossible to fit** (a net for `nbits` cannot be expressed within
  `maxlines` lines), the generator must **refuse**: print a line starting with
  `OVER_BUDGET`, exit non-zero, and **not create** an output file. Naively emitting a
  too-large net is a failure.
- Produce the shipped artifact by running:
  `python3 /app/gen-gate.py 4096 /app/gate.def 32000`
- Mind the width: the oracle will generate bit vectors of exactly `nbits` bits for
  your net, and XOR is a bijection, so a 4096-bit net has exactly 4095 gate lines.

## Part 5 — substitution-table generator (`/app/gen-table.py`)

A calibration LUT must map every source index to a destination index. The table must
be **complete** (every source appears exactly once, every destination distinct) and
fit under **both** a row cap and a byte cap.

**Contract**
```
python3 /app/gen-table.py <spec.json> [out.csv]     # out defaults to /app/table.csv
```
`spec.json`:
```json
{ "bits": 8, "a": 7, "b": 13, "cap_rows": 300, "cap_bytes": 4096 }
```
- `bits` gives the width: indices are `0 .. 2**bits - 1`.
- The intended mapping is `dst = (a*src + b) mod (2**bits)`. `a` is always odd, so the
  map is a bijection.
- Write CSV rows `src,dst` in uppercase hex, one pair per line (`00,0D`). Row count
  must be ≤ `cap_rows` and file size ≤ `cap_bytes`.
- If the caps **cannot** be satisfied for the given `bits` (e.g. a byte cap smaller
  than the minimum table size), refuse: print a line starting with `OVER_LIMIT`,
  exit non-zero, and create no file.
- Produce the shipped artifact by running:
  `python3 /app/gen-table.py /app/fixtures/table_spec.json /app/table.csv`
- The plant re-checks completeness, distinctness, mapping correctness, and both caps
  on your deliverable and on regenerated tables from fresh specs.

## Part 6 — compressed tiny source (`/app/tiny-source.py`)

Grove renders a 24×40 visual frame into firmware. The source for the renderer must be
**tiny enough to ship compressed**: `gzip(tiny-source.py)` must be **≤ 400 bytes** and
the raw source **≤ 700 bytes**, and the source must **not embed the rendered data**
(no pixel/character literal of the output may appear in the source). It must compute
the frame from arithmetic alone.

**Contract** — running `python3 /app/tiny-source.py` must print exactly 24 lines of
exactly 40 characters, newline-terminated, where the character at row `y` (0..23),
column `x` (0..39) is
```
S = " .:-=+*#%@"
chr = S[ (y*19 + x*7 + (y*x*5) % 11) % 10 ]
```
The plant verifies the output byte-for-byte, the two size caps, that no output line
appears inside the source, and the number report:

`/app/compressed-sizes.json`:
```json
{ "source_bytes": 359, "gzip_bytes": 287 }
```
(must equal the real measured values of your `/app/tiny-source.py`).

---

## Plant verification (summary — design against it)

- All six tools will be re-run on fresh hidden inputs (from `/tests/hidden`): three
  tile puzzles (shallow, **trivial start==goal**, deep), three expression specs
  (single number, subtraction, division-heavy), three oracle contexts (small, medium,
  and near-maximum log lengths), a feasible gate regen plus an **over-cap** regen that
  must be refused, and table specs including one with **impossible caps** that must be
  refused.
- Every hard bound is enforced: 32000-line gate cap, table row/byte caps, 40-probe
  oracle budget, 700/400-byte source/gzip caps.
- Fixtures in `/app/fixtures/` and instruments in `/app/bin/` are read-only: do not
  modify them; your deliverables go next to them in `/app`.