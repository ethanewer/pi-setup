# drift-upland — multi-competency solver bundle

You are given a small set of five independent algorithm tasks. You must deliver a
single Python CLI program **`/app/solve.py`** that solves all of them, plus a
path file **`/app/moves.txt`** for one fixed sliding-tile puzzle.

`/app/solve.py` must be invokable as:

```
python3 /app/solve.py <subcommand> <input.json> <output>
```

The five subcommands are `series`, `meeting`, `mahjong`, `pursuit`, `puzzle`.
Every subcommand reads a JSON input file (exact schema below), computes a result,
and writes a JSON output file — **except** `puzzle`, which writes a plain-text
path file containing one tile label per line.

The supplied fixtures in `/app` (`sample_series.json`, `sample_meeting.json`,
`sample_mahjong.json`, `sample_puzzle.json`, `sample_pursuit.json`) are there for
you to test against; do not modify them. The automated verifier runs your
`/app/solve.py` on the visible fixtures **and** on hidden inputs of each type and
checks every result.

Do not rename, move, or delete the required deliverables. Keep your solution in
a single file: `/app/solve.py`.

---

## 1. `series` — count contiguous above-threshold runs

**Input JSON:**
```json
{"series": [55, 12, 60, 61, 58, 4, 40, 41, 42, 43, 40, 39, 50],
 "threshold": 40, "min_len": 3}
```

A *sample* is **active** when its value is `>= threshold` (inclusive: a sample
exactly equal to the threshold counts as active). A *run* is a maximal contiguous
block of active samples. Count only runs whose length is `>= min_len`.

- Two active runs separated by a single inactive sample are **two separate runs.**
- A run at the very start or very end of the series still counts (its length is
  all that matters).
- `min_len` is inclusive: a run exactly `min_len` long counts; one of length
  `min_len - 1` does not.
- An empty series has `0` runs. Negative values are allowed and `0 >= threshold`
  counts as active when `threshold <= 0`.

**Output JSON:** `{"runs": <integer>}`

Example: with the input above, the active blocks are `[55]` (1 long, not
counted), `[60,61,58]` (counts), `[40,41,42,43,40]` (counts), `[50]` (not
counted) → `{"runs": 2}`.

---

## 2. `meeting` — feasible venue + earliest start time

You hold a one-hour meeting. Time is expressed in absolute minutes on a shared
day (0..1440, whole-hour starts only). Choose a venue and a literal starting time
`S` that is an integer multiple of `60`.

**Input JSON:**
```json
{
  "people": [
    {"name": "Alice", "cuisines": ["italian", "thai"],
     "free_start": 480, "free_end": 1200,
     "commute": {"noodle_place": 30, "meridian_cafe": 15}}
  ],
  "venues": [
    {"name": "meridian_cafe", "cuisine": "italian",
     "open_start": 600, "open_end": 1320}
  ]
}
```

A venue `v` and start `S` (a whole hour, so `S % 60 == 0`) is **feasible** when
all of the following hold for every person `p`:

1. `v`'s `cuisine` is listed in `p.cuisines` (everyone can eat there).
2. `v` is present as a key in `p.commute` (the person can travel there at all).
3. Scheduling window: `p.free_start + p.commute[v] <= S` (the person can leave
   home at/after they are free and still arrive by the start).
4. Meeting fits their schedule: `S + 60 <= p.free_end` (the whole one-hour slot
   lies inside `free_end`).
5. The venue is open for the whole meeting: `v.open_start <= S` and
   `S + 60 <= v.open_end`.

**Output JSON:** choose the feasible `(S, v)` with the **smallest `S`**; among
ties at that `S`, pick the venue name that sorts **smallest lexicographically**.
Write:
```json
{"venue": "meridian_cafe", "time": 720}
```
If **no** venue/time is feasible, write `{"venue": null, "time": null}`.

The meeting occupies exactly 60 minutes; a venue whose open window or a person
whose free window ends *exactly* at `S + 60` is still fine (≤ is inclusive). A
long commute pushes the earliest possible `S` later than the venue's opening.

---

## 3. `mahjong` — winning-hand completions

**Input JSON:**
```json
{"tiles": ["M1", "M1", "M1", "M2", "M2", "M2", "M3", "M3", "M3", "M4", "M5", "M6", "M9"]}
```

13 tiles are given, each a two-character code: suit letter `M` (man), `P` (pin),
or `S` (sou) followed by a rank `1`..`9`, **or** a single honor tile among
`E, S, W, N, R, G, B` (East, South, West, North, Red dragon, Green dragon, White
dragon). *Note: `S` alone is the honor South; `S1`..`S9` are sou tiles — they are
distinct tile types.*

A 14-tile hand is **winning** if it can be partitioned into exactly **4 melds
plus 1 pair**. A meld is either a **triplet** (three identical tiles) or a
**sequence** (three consecutive ranks *of the same suit*; honor tiles only form
triplets, never sequences as they have no rank order). The pair is two identical
tiles.

For each of the **34 standard tile types** that could be added to the given 13
tiles, determine whether the resulting 14-tile hand is winning. Never add a 5th
copy of a tile type already held (at most 4 copies of any type may exist).

The classic subtlety is that a given tile of rank `r` may serve as part of a
sequence *or* as a triplet, and either choice can change the answer — you must
search both possibilities (e.g. try removing a pair and then decomposing the
remaining 12 tiles by, at each step, taking the smallest present tile as a
triplet or as the start of a sequence; this greedy-on-smallest decomposition is
complete and correct).

**Output JSON:** the sorted list of tile-type codes that complete a winning hand:
```json
{"winning_tiles": ["M9"]}
```
If no completion exists the list is empty. A malformed hand that does **not**
contain exactly 13 tiles yields `{"winning_tiles": []}` (no completions).

---

## 4. `pursuit` — plan an evasion path

**Input JSON:**
```json
{"rows": 4, "cols": 5, "walls": [], "player": [0, 0],
 "opponent": [3, 4], "horizon": 8}
```

You control the **player** on an `rows × cols` grid (row index 0..rows-1, column
0..cols-1). Some cells are blocked (given as `walls`: a list of `[r, c]`). The
**opponent** is a single greedy chaser. The game runs for exactly `horizon`
turns. **You must output one player move per turn** and survive all `horizon`
turns without being captured.

**Turn mechanics** (the verifier replays exactly this):

1. Turn starts with player at `P`, opponent at `E` (`P != E`).
2. You choose a player move from `U, D, L, R, S` (up/down/left/right/stay).
   The player must stay in bounds, not enter a wall cell, and **must not step
   onto** the opponent's current cell.
3. The opponent then chases. It considers its **own** current cell plus each of
   the four neighbours that are in bounds and not walls. It moves to the reachable
   cell with the **smallest Manhattan distance** to the player's new cell
   `(|dr|+|dc|)`; ties break in this fixed order: `U, D, L, R`, then staying.
4. If the opponent's chosen cell equals the player's cell, the opponent captures
   the player and the game ends (you lose).

Because capture can only happen on step 4, to survive a turn the player must not
be adjacent at a moment when the chaser can land on it — keep clear.

**Output JSON:** exactly `horizon` moves:
```json
{"moves": ["D", "U", "D", "U", "D", "U", "D", "U"]}
```

The verifier simulates the game above with your exact move list and confirms the
player survives all `horizon` turns (never captured, no illegal cell, no walking
onto the chaser) and that the list has length exactly `horizon`. Plan carefully
against the described greedy-chaser rule; a strategy that merely races toward the
chaser, stops moving, or leaves the board gets caught.

Edge: `horizon == 0` means no moves and you win trivially (output `{"moves": []}`).

---

## 5. `puzzle` — optimal sliding-tile path

**Input JSON:**
```json
{"start": [[1,2,3],[5,0,6],[4,7,8]],
 "goal":  [[1,2,3],[4,5,6],[7,8,0]]}
```

A square sliding-tile board (the `0` is the blank). A legal move slides a tile
**edge-adjacent** to the blank into the blank's cell. Find a **minimum-length**
sequence of moves (a shortest path) from `start` to `goal`, i.e. a BFS/IDA* /
A* over board states.

**Output:** write the path to the output file as **one tile label per line** —
the label of the tile that slides into the blank at each step (tiles are the
numbers `1..8`, never `0`). Empty path for an already-solved board. All given
instances are solvable.

The verifier replays your labels (each must be adjacent to the blank at that
moment), checks the final board equals `goal`, detects any repeated state (a
cycle), and requires the number of moves to equal the true BFS shortest distance.

**Deliverable `/app/moves.txt`:** run your solver on
`/app/sample_puzzle.json` (start `[[1,2,3],[5,0,6],[4,7,8]]`, goal the identity)
and write the optimal path to `/app/moves.txt` using the same one-tile-per-line
format. The verifier replays and optimally-checks this file exactly as above.

---

## Deliverables summary

- `/app/solve.py` — the multi-command CLI above (all five subcommands).
- `/app/moves.txt` — optimal tile path for the visible `sample_puzzle.json`.

The verifier executes `/app/solve.py` on the visible fixtures and on hidden
inputs for every subcommand, and replays `/app/moves.txt`. Everything must hold.
