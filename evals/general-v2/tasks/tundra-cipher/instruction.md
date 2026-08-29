# tundra-cipher — The Frostline arrangement engine

You must build a scheduling/arrangement engine for a winter backcountry lodge.
It reads a **case directory**, solves four tightly specified sub-problems, and
writes three result files. Your deliverable is one program that works for the
supplied **visible case** **and** for any other case that uses the same file
layout — the automated verifier runs your program on **hidden case
directories**.

Deliverables under `/app`:

| path | meaning |
|---|---|
| `/app/solver.py` | a single Python CLI (see below) |
| `/app/grid.txt`   | solved 9×9 grid, exact serialization (sub-problem A) |
| `/app/answer.txt` | packing count, a single integer (sub-problem B) |
| `/app/plans.txt`  | schedule + neighbour table (sub-problems C and D) |

`/app/solver.py` must be invokable as:

```
python3 /app/solver.py <case_dir> <out_dir>
```

It reads the case directory and writes `grid.txt`, `answer.txt`, and
`plans.txt` **into `out_dir`** (which may already exist). It must work from
scratch on *any* case directory. Do not hard-code the visible case's numbers —
the same code must run on hidden cases. Do not read `/tests` or anything outside
the `<case_dir>` and `<out_dir>` you are given.

A complete visible instance is fixed at `/app/instance/` (read it; never modify
it). Produce the visible deliverables by running your solver on it:

```
python3 /app/solver.py /app/instance /app
```

That creates `/app/grid.txt`, `/app/answer.txt`, `/app/plans.txt`. The verifier
also runs `/app/solver.py` on **hidden case directories** that follow the same
four file formats with different (sometimes edge / malformed) data, and expects
the same rules applied there.

---

## The case directory (everything your solver reads)

It contains exactly four files:

* `grid.txt`   — the 9×9 puzzle (sub-problem A)
* `packs.txt`  — packing-subsets input (sub-problem B)
* `roster.txt` — weekly schedule input (sub-problem C)
* `table.txt`  — round-table seating input (sub-problem D)

Throughout, a `#` begins a comment running to the end of the line; strip it and
surrounding whitespace before parsing, and ignore blank lines.

---

## Sub-problem A — the 9×9 grid (writes `grid.txt`)

The input `grid.txt` is a **9-by-9 Sudoku puzzle**: exactly 9 rows, each with 9
space-separated integers. `0` marks an empty cell; `1..9` is a fixed clue. Every
provided puzzle has a **unique** completed solution and is solvable by
constraint backtracking.

**Output `grid.txt`:** the completed grid in the same layout — **exactly 9
lines**; each line has **exactly 9 space-separated digits** `1..9` (no trailing
whitespace, no extra blank line at the start or end). The grid is the unique
valid Sudoku: every row, every column, and every 3×3 box contains each of `1..9`
exactly once, and every clue is preserved.

---

## Sub-problem B — the packing count (writes `answer.txt`)

**`packs.txt`** holds a **0/1 packing-subsets** problem:

* line 1: an integer **capacity** `cap`.
* the remaining lines: a list of integer **item weights**, split across lines,
  any number ≥ 0 of items (every integer on every later non-comment line is a
  weight).

A **feasible packing** is a subset of the listed weights whose **total is ≤ cap**.
Each item is **at most once** (items with equal weight are still distinct items —
using any one uses it up). An item with weight `<= 0` is never placeable; a
weight `> cap` can never be in a feasible subset.

**`answer.txt`** holds **the total number of distinct feasible packing subsets**,
exactly. The empty subset is feasible whenever `cap >= 0`, so the count is ≥ 1
then and exactly **0** when `cap < 0`.

Examples: `cap = 0` with any positive weights ⇒ **1** (only the empty subset).
`cap = 2`, weights `[1, 1]` ⇒ feasible subsets: `{}`, `{first}`, `{second}`,
`{both}` ⇒ **4**.

Hidden instances are large (30–40 items): brute-forcing all `2^n` subsets is
infeasible. Count with dynamic programming so that no subset is missed and none
is double-counted. The exact result can be many hundreds of millions — write it
in full.

**`answer.txt`** must contain the bare integer with **no trailing newline** and
**no trailing whitespace** (writing `echo` or `cat >` typically adds a newline —
write the integer with no line ending).

---

## Sub-problem C — the schedule (first block of `plans.txt`)

**`roster.txt`** keywords (one per line, in any order):

* `window <HH:MM> <HH:MM>`  — business-hours window (inclusive start, exclusive
  end). Candidate slots must lie wholly inside it.
* `lunch <HH:MM> <HH:MM>`   — daily lunch break (inclusive start, exclusive
  end). No slot may overlap it.
* `duration <minutes>`      — fixed slot length in minutes (15/30/60/120).
* `days <D1> <D2> ...`      — ordered list of schedulable **day labels**. Only
  these days are scanned (day-of-week rule). A label such as a weekend day IS
  schedulable if present; anything not present is never scanned. Days are
  considered in file order.
* `person <NAME> <DAY> <HH:MM> <HH:MM>` — one PERSON's availability on that day
  as an inclusive-start/exclusive-end interval. A person not having an entry on
  a given day is not available that day (but see rule 4).

A **candidate slot** begins at `window_start`, then `window_start+15`,
`window_start+30`, … (a 15-minute grid), lasts `duration` minutes. It is **valid**
iff all hold simultaneously:

1. `slot_start >= window_start` and `slot_end <= window_end`,
2. `slot_end <= lunch_start` **or** `slot_start >= lunch_end` (entirely outside
   the lunch break),
3. the associated day is in the `days` list,
4. **every person that has an entry on that day** fully covers the slot
   (`entry_start <= slot_start` **and** `entry_end >= slot_end`). If even one
   entry for that day fails to cover it, the slot is invalid. Persons with **no**
   entry that day are ignored entirely. A person with a zero-length entry
   (`HH:MM` == `HH:MM`) on a day covers nothing, so every slot on that day is
   invalid.

**`plans.txt`** begins with the literal header line `[SLOTS]` followed by one
line per valid candidate, in **scan order** (day-major, then time-ascending):

```
<DAY> <HH:MM>
```

`HH:MM` is the slot start, zero-padded (`08:00`, `09:15`, …); `<DAY>` is the day
label verbatim.

---

## Sub-problem D — the neighbour table (second block of `plans.txt`)

**`table.txt`**:

```
focus <NAME>
round <NAME1> <NAME2> ...
round <NAME1> <NAME2> ...
```

The focus is the first-token `focus` line. Each `round` line lists names seated
clockwise around a (circular, wrap-around) table. In a given round of length `n`
where the **focus** is at 0-based index `i`, its immediate neighbours are the
names at `(i-1) mod n` and `(i+1) mod n`; each yields the pair `(focus,
neighbour)`. Adjacency is positional (rotating the seating does not change it).

Edge rules:

* a round of length `0` or `1` has no neighbours;
* a round not containing the focus is skipped;
* a round of length `2`: the other name is both neighbours — emit **one** pair
  (deduplicated);
* collect **distinct** pairs across all rounds, then **sort** them
  lexicographically by the *neighbour* name;

Each distinct pair is written on its own line as `<focus> <neighbour>` (focus
always first).

After the `[SLOTS]` block, `plans.txt` continues with the header line `[TABLE]`
followed by the sorted neighbour-pair lines.

---

## The complete `plans.txt` layout

```
[SLOTS]
<valid slot lines, one per row, in scan order>
[TABLE]
<neighbour pair lines, sorted>
```

Both headers are always present, in this order. A case with no valid slots has
`[SLOTS]` with no rows beneath it; a case with no pairs has `[TABLE]` with no
rows beneath it.

---

## What must exist when you are done

* `/app/solver.py`   — python3-runnable on any case directory.
* `/app/grid.txt`    — solved grid for the visible instance.
* `/app/answer.txt`  — packing count for the visible instance (no trailing NL).
* `/app/plans.txt`   — visible schedule + neighbour table.

The verifier independently recomputes the expected results (for both the
visible and every hidden case) and compares them with what `/app/solver.py`
produces **and** with the contents of `/app/{grid.txt,answer.txt,plans.txt}`.
Be exact — row counts, spacing, header lines, zero-padding, sorting and the
no-trailing-newline rule for `answer.txt` all matter. You are given the instance,
never the test suite.