# amber-ledge — board-engines toolkit

You are building five small, independent puzzle/board-game primitives in
`/app`. Everything is specified exactly; read carefully and implement **all
five** deliverables. You are scored on behaviour of every one of them.

Environment: Node.js (`node`) and Python 3 (`python3`) are both installed.
Write real programs; nothing here requires third-party libraries.

---

## Deliverable 1 — `/app/game.js` (pure JavaScript, no imports)

A pure-function per-turn "cell decision" module. The file must export an
object with a method `decide(cell)`:

```js
module.exports = { decide: decide };
```

It must be a **plain function** (not a class) and must **not** `require()` or
`import` anything (no external libraries). No networking, no randomness.

**Input `cell`** — the state of an ordered puzzle line:

```json
{
  "line":   [ { "tile": 5, "open": true }, { "tile": 2, "open": false }, ... ],
  "cursor": 1
}
```
- `line` is an ordered array of tile objects.
- Each tile has a numeric `tile` value (>= 0) and a boolean `open`.
- `cursor` is the index of the currently-active tile.

**Behaviour:** `decide` returns one string — the action the cursor must take:
- `"left"`  — move to the adjacent tile on the left, **if** it exists and its
  `open !== false` (a missing `open` field counts as open).
- `"right"` — move to the adjacent tile on the right, under the same rules.
- `"stay"`  — when neither move is allowed, or the state is malformed.

**Choosing among allowed moves:** pick the direction whose target tile has
the **larger** `tile` value. On a **perfect tie** prefer `"right"` over
`"left"`. A neighbour that is `open: false`, that is out of bounds, or that
does not exist cannot be chosen.

**Edge cases to handle:** empty `line`; `cursor` out of bounds /
not-a-number; both neighbours closed or absent; `line` missing or not an
array. In all these return `"stay"`.

Example: `cell = { line:[{tile:1},{tile:5},{tile:9}], cursor:1 }` with all
`open` true → `"right"`.

---

## Deliverable 2 — `/app/chess.py` (chess legal move generation)

A from-scratch chess **legal** move generator. It must handle full castling
rights, en-passant, and all four promotions, and identify which legal moves
give checkmate in exactly one move.

Position notation is FEN-style: `"r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"`.

Command-line interface (two subcommands):
```
python3 /app/chess.py legal "<fen>"   -> JSON array of legal moves (UCI-style)
python3 /app/chess.py mate  "<fen>"   -> JSON array of mate-in-one moves
```

- Each move is a UCI-style string: `<from><to>` with squares as file
  letter (`a`–`h`) + rank (`1`–`8`).
- Castling: king move only, `e1g1` / `e1c1` (white) and `e8g8` / `e8c8`
  (black).
- En passant: the capturing pawn's `<from><to>` into the empty en-passant
  target square (e.g. `e5d6`), removing the captured pawn.
- Promotion: append the promoted piece **lowercase** letter: Q, R, B or N
  (e.g. `e7e8q`, `a7a8n`). Return **all four** promotion options.
- "legal" must return the **complete** move set, from-castling-rights
  respected, king cannot move into / stay in check, pins respected, and the
  side not allowed to leave its own king in check.
- "mate" must return **only** the moves that deliver immediate checkmate
  (the resulting position leaves the opponent in check with zero legal
  reply). If no move checkmates, print `[]`.

Castling requires: the king and matching rook on their starting files, the
castling-right character present in the FEN (white `K`/`Q`, black `k`/`q`),
all intervening squares empty, the king not currently in check, and the king
not passing through or landing on an attacked square.

Output is a JSON list of strings. JSON `[]` when there are no such moves.

---

## Deliverable 3 — `/app/planner.py` (batch action-plan evaluator)

`python3 /app/planner.py <input.json> <output.json>` reads a JSON **batch of
action plans** and writes a JSON list of **cumulative rewards**, aligned by
index with the input plans.

`input.json` is a list; each plan is a list of action **strings**, e.g.
```
[ ["gather","chop","forge","market"], ["free","gather"], [] ]
```
`output.json` must be a JSON list of the same length in the same order, where
entry `i` = the total cumulative reward of running plan `i` sequentially.

**Magazine step model** — a running state tracks three materials `f`, `w`,
`o` (all start at 0). Each action adds a reward and may update state:

| action   | effect                                            | reward |
|----------|---------------------------------------------------|--------|
| `gather` | `f += 1`                                          | 5      |
| `chop`   | `w += 2`                                          | 7      |
| `free`   | `f += 1`                                          | 1      |
| `quarry` | `o += 1`                                          | 1 if `o` was 0 before, else 6 |
| `forge`  | requires `w >= 2` (consumes 2), else nothing      | 14 if done, else 0 |
| `market` | no state change                                   | current `f` |
| `idle`   | no change                                         | 0      |

Cumulative reward = running sum of these per-action rewards across the
plan's actions.

Edge rules: an **empty plan** → reward 0. An **unknown action** (not in the
table) is skipped (reward 0). A plan that is **not a list** → reward 0. A
`forge` put early with `w < 2` yields 0 and is not consumed. `market`
reads the current `f`. Order within a plan matters.

---

## Deliverable 4 — `/app/mahjong.py` (hand classifier + aggregation)

`python3 /app/mahjong.py <path>` where `<path>` is **either** a single
`.json` hand file **or** a directory of `.json` hand files. Every hand file
under the directory must be read and classified.

- Single file → print one JSON line: `{"file": "<basename>", "pattern": "<p>"}`
- Directory  → print a JSON array of those objects, **sorted by `file` name**.

Tile codes are 2-char strings:
- suited: `1m`..`9m`, `1p`..`9p`, `1s`..`9s`
- winds: `East`, `South`, `West`, `North`
- dragons: `R`, `G`, `B`

A hand is a JSON list of 14 tile codes. Classify each hand into exactly one of:

- `seven_pairs` — all 14 tiles arrange into **exactly seven pairs**: every
  distinct tile occurs exactly twice (`2m,2m,3s,3s,...` seven kinds).
- `thirteen_orphans` — the hand uses exactly the 13 orphan tiles (the three
  terminals `1m,9m,1p,9p,1s,9s` plus all four winds plus all three dragons),
  each orphan present at least once, and because there are 14 tiles, exactly
  **one** orphan appears twice.
- `neither` — any other valid 14-tile hand.
- `malformed` — the file is not a list, is not exactly 14 tiles, or contains
  a tile code outside the set above.

A hand cannot be both winning patterns at once. Per-file aggregation must
cover **every** file in the directory (including malformed ones) with the
exact `{"file","pattern"}` shape and sorted-by-name output.

---

## Deliverable 5 — `/app/serialize.py` (canonical serialization)

`python3 /app/serialize.py <input.json> <output.json>`

`input.json` is a JSON **list of boards**; a board is a **list of rows**, each
row a list of tile integers (0–99). Write `output.json` as a JSON list of the
same length/order where each board becomes its **canonical fixed-length
string**: the concatenation, row-major, of each tile **zero-padded to exactly
two digits**. No separators. Length equals `rows × cols × 2`.

Examples:
- `[[5,0,7],[1,2,3]]` → `"050007010203"`
- `[[9]]` → `"09"`
- `[[12,34],[56,78]]` → `"12345678"`

Validation — a single malformed board must not corrupt the others:
- board that is not a non-empty list of rows → `"INVALID"`
- a row not a list, rows of differing length, a non-integer value, a boolean,
  or a value outside `0..99` → that board is `"INVALID"` (others unaffected)
- leading zeros are mandatory (tile `7` → `"07"`).

---

## General requirements

- Create **all five** files at the exact paths `/app/game.js`, `/app/chess.py`,
  `/app/planner.py`, `/app/mahjong.py`, `/app/serialize.py`.
- Every program must be runnable by the stated CLI (each is invoked fresh by
  the grader). No server, no interactive prompt.
- Output/trailing whitespace after the JSON/action is fine; the content must
  match. `chess.py` prints a single JSON list line. `planner.py` / 
  `serialize.py` must write the JSON to the requested output file.
- Do **not** modify anything else and do not store results outside your /
  deliverable files; the grader only cares about the five programs' behaviour
  from a clean invocation.