# tundra-engine

You are building a small, general-purpose **game & maze search bench** solver for a
frozen-wastes expedition ("tundra-engine"). You will write ONE self-contained Python
3 program `/app/solve.py` plus produce `/app/answer.json` by running that program on
a provided spec file.

## Deliverables

| Path | What it is |
|------|------------|
| `/app/solve.py` | A general solver. Given any `INPUT.json`, writes the answer file described below. Must handle *new* cases of every type (the verifier runs it on hidden inputs it has never shown you). |
| `/app/answer.json` | The result of running `python3 /app/solve.py /app/spec.json /app/answer.json` inside `/app`. |

Do **not** modify `/app/spec.json`. Produce `/app/answer.json` strictly by invoking your
solver on `/app/spec.json`.

## CLI contract

```
python3 /app/solve.py [INPUT.json [OUTPUT.json]]
```

- `INPUT.json` default `/app/spec.json`; `OUTPUT.json` default `/app/answer.json`.
- `INPUT.json` is a JSON object: `{"cases": [ <case>, ... ]}`. `cases` may be absent
  or empty — a valid solver then writes `{"answers": {}}` and exits 0.
- Every case is a JSON object carrying a unique `"id"` and a `"type"` from
  {`tiles`, `snapshot`, `mahjong`, `connect`, `maze`}. Ignore any extra keys.
- Output format: `{"answers": { "<id>": { ...ret... } }}` where each `{...ret...}`
  echoes the case's `id` and `type` and adds the type-specific fields below.
- Exit code 0 always on well-formed input.

Every case result **must include** `"id"` and `"type"` copied from the input case.

---

## 1) `type: "tiles"` — optimal sliding-tile solver

A `rows x cols` rectangular board of integers holding every value `0..rows*cols-1`
exactly once; `0` is the **blank**. A move slides an adjacent tile (up/down/left/right
of the blank) into the blank. This is the classic sliding-blocks puzzle.

Input:
```json
{"id": "t1", "type": "tiles", "grid": [[1,2,3],[4,0,6],[7,5,8]]}
```
Optional `"goal"` (same shape). If omitted, the goal is the canonical solved
arrangement: rows-major values `1,2,...,rows*cols-1` with `0` in the bottom-right
cell (i.e. `[1,2,...,cols]` first row, ..., last row `[...,0]`).

Output fields:
- `rows`, `cols` — board dimensions.
- `solvable` — boolean parity test w.r.t. the goal.
- `solved` — boolean: `solvable` AND a solution was found.
- `min_moves` — the **minimum** number of moves to reach the goal; `-1` if
  unsolvable or no solution found.
- `canonical_initial`, `canonical_goal` — the fixed-length zero-padded string of the
  initial and goal boards (see §2 encoding).
- `states` — list of canonical strings, one per move **after** that move
  (length `== min_moves`; empty when already solved or unsolvable).
- `path` — a tab-separated optimal move list, one line per move, each line
  `sr,sc\tdr,dc\ttileValue`, meaning *the tile whose value is `tileValue` slides from
  `(sr,sc)` into the blank cell `(dr,dc)`* (they are 4-adjacent). `move_count` = number
  of lines.
- `move_count` — `== min_moves`.

**Edge cases hidden tests probe:**
- A single-cell board `[[0]]` → already solved, `min_moves == 0`, empty `path`.
- Already-solved boards → `min_moves == 0`.
- Unsolvable parity (e.g. some `2x2` swaps) → `solvable == false`, `min_moves == -1`.
- The path must be **optimal**: a hidden check re-runs its own A*/BFS and requires
  `min_moves` and `move_count` to equal the true optimum on small boards, and verifies
  the path is `move` sequence of legal adjacent slides that reaches the exact goal,
  and that each entry of `states` equals the board after that move.

---

## 2) `type: "snapshot"` — canonical zero-padded serialization

Input:
```json
{"id":"s1","type":"snapshot","grid":[[0,1],[2,3]]}
```
Output: `{"valid": bool, "canonical": string}`.

- `valid` is True iff `grid` is a non-empty rectangular list of list of ints where each
  value is in `0..99`.
- When valid, `canonical` is each cell formatted with **exactly two digits** (`0` → `"00"`,
  `7` → `"07"`, `99` → `"99"`), concatenated in row-major order. Length is always
  `2 * rows * cols`.
- When invalid, `canonical` is `""`.

**Edge cases probed:** empty grid; ragged rows; negative or `>99` values → all invalid;
normal grids of any size → exact canonical string.

---

## 3) `type: "mahjong"` — seven-pairs and thirteen-orphans win detection

Tiles use codes: suits `A`,`B`,`C` with ranks `1..9` (`"A1".."A9"`, etc.) plus seven
honor tiles `"H1".."H7"`. A hand is a list of 14 tile codes.

Input: `{"hand": ["A1","A9","B1","B9","C1","C9","H1","H2","H3","H4","H5","H6","H7","H1"]}`

Output: `{"valid": bool, "win": bool, "pattern": "seven_pairs"|"thirteen_orphans"|"none"}`.

- `valid` is true iff the hand has exactly 14 tiles and every code is in the vocabulary.
- Define the **terminal/honor set (TH)** = `{A1,A9,B1,B9,C1,C9,H1,H2,H3,H4,H5,H6,H7}`.
- **seven_pairs**: the 14 tiles form exactly 7 pairs — the multiset of tile counts is
  seven values each equal to 2 (so *no* tile appears 4 times; a quad breaks it).
- **thirteen_orphans**: the hand contains each of the 13 TH tiles at least once and
  nothing outside TH; with 14 tiles that means exactly one TH tile appears twice and the
  other 12 appear once.
- If both could match, `thirteen_orphans` takes precedence.
- `pattern == "none"` and `win == false` for a valid non-winning hand and for any
  invalid hand.

**Edge cases probed:** a hand of the wrong length (e.g. 13 tiles); an unknown code;
a seven-pairs hand that contains a quadruple (not a win); a 13-orphans hand with the
duplicate on a terminal vs an honor; honor-only seven pairs.

---

## 4) `type: "connect"` — block a four-in-a-row threat

Board: list of equal-length strings over `'O'` (opponent), `'X'` (ours), `'.'` (empty).

Input: `{"board": ["OOO..",".....",".....","....."]}`

Output: `{"block": [r,c] | null, "threats": int}`.

A **threat-end cell** is an empty cell that is the open end immediately adjacent to a
contiguous line of **exactly 3** opponent (`O`) tiles, along any of the four lines
(horizontal, vertical, and both diagonals). You must block such a threat by returning
an empty cell that stops the four-in-a-row if our stone is placed there.

- `threats` = number of distinct threat-end cells.
- `block` = any one threat-end cell as `[row, col]`, or `null` when there is no
  immediate threat.

**Rules / edge cases:** a run of exactly 4 `O`'s is *not* a ("blockable on an end") —
only runs of exactly 3 with at least one open end count. Runs complete/handed at the
board edge or blocked by an `X` or another `O` give no open end there. Diagonal threats
count too. When several cells qualify, any one is acceptable.

---

## 5) `type: "maze"` — shortest-turn routing under a budget

Board: list of equal-length strings over `{'#', '.', 'S', 'G'}`, where `#` is a wall,
`.` passable, and there is exactly one `S` and one `G`. One move = step to a
4-neighbour (no diagonal), through a passable cell.

Input:
```json
{"id":"m1","type":"maze","grid":["S...",".##.","...G"],"max_turns":5}
```
Output:
```json
{"reachable":bool,"min_turns":int,"within_budget":bool,"moves":"URDL-string"}
```
- `reachable` is false if `S`/`G` is missing or `S` cannot reach `G`; then
  `min_turns == -1`, `within_budget == false`, `moves == ""`.
- `min_turns` = the **minimum** number of moves `S -> G` (a shortest path).
- `within_budget` = (reachable and `min_turns <= max_turns`). Treat a missing/`null`
  `max_turns` as unlimited (within_budget true when reachable).
- `moves` = a shortest path as an uppercase ``URDL` string (`U` up, `D` down, `L` left,
  `R` right); empty if not reachable or `min_turns == 0`.

**Edge cases probed:** `S` or `G` missing; a wall that fully separates `S` from `G`;
short paths that still exceed a tight `max_turns` (budget decision); a large
`max_turns`; and the requirement that the returned path is actually minimal (a hidden
BFS recomputes the length and replays `moves` back onto the board to the goal).

`max_turns` is the "turn budget" — your decisions must be **efficient** enough that the
returned `moves` and `within_budget` are exact, never merely reached.

---

## General requirements & what the verifier does

1. `/app/solve.py` must be a *general* solver, not a hard-coded answer table for the
   visible cases. The verifier copies each hidden fixture to a temp path and runs
   `python3 /app/solve.py <fixture> <tmp_out>` and compares every answer against an
   independent oracle **and** an independent re-implementation (its own BFS/searches).
2. `/app/answer.json` must equal a fresh run of your solver on `/app/spec.json`; the
   verifier re-runs it and compares byte-for-byte as JSON.
3. No special handling is needed for extra keys in a case object; ignore them.
4. Do not read `/tests` or leave code that depends on files outside `/app` (the verifier
   never mounts them into your workspace).

A correct, general solver earns a reward of 1; any wrong field, non-minimal move list,
illegal slide, or missed edge case earns 0.