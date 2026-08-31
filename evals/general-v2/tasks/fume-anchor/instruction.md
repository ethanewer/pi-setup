# fume-anchor: derive the activation payload

The **fume-anchor** beacon refuses to arm until it receives a numeric payload.
The activation recipe is **not written in one place**: it is scattered across
four plain-text artifacts inside a *state directory*. Your job is to read the
clues, combine them with exact integer arithmetic, and produce the payload
the beacon expects.

Working directory: `/app`. The visible state directory is `/app/state`
(do **not** modify anything under `/app/state`). Python 3.12 is available as
`python3`.

## State-directory layout

A state directory contains exactly these clue artifacts (paths are relative
to the directory):

- `deploy.env` — `KEY=VALUE` lines.
- `rotation.txt` — slot assignment lines.
- `docs/epoch.md` — a markdown note hiding the epoch prime.
- `nodes.list` — a node roster.

## Derivation rules (apply exactly, in this order)

1. **Base `B`** — from `deploy.env`: the value of the key `SERIES_BASE`,
   parsed as a signed integer. Skip blank lines and lines whose first
   non-whitespace character is `#` (comments/decoys). Split each remaining
   line on the **first** `=`; strip whitespace from key and value. Any key
   other than `SERIES_BASE` is a distractor. If `SERIES_BASE` appears more
   than once, the **last** occurrence wins.
2. **Multiplier `M`** — from `rotation.txt`: each assignment line has the
   form `slot <name> = <int>` (whitespace around tokens is flexible). `M` is
   the value of the slot named exactly **`anchor`**. Slot names must match
   exactly — `anchorx`, `anchor-2`, `anchor2` are distractors. Lines of any
   other shape (e.g. `rack bravo = 9`), blank lines, and `#` comment lines
   are ignored. If more than one `anchor` slot appears, the **last** one
   wins.
3. **Prime `P`** — from `docs/epoch.md`: find the **first** line containing
   the literal token `epoch-prime`. On that line, take the text after the
   **last** `:` character, strip surrounding whitespace, and parse it as an
   integer. That is `P`. Any later mention of `epoch-prime` is a decoy and
   must be ignored.
4. **Offset `N`** — from `nodes.list`: `N` is the number of lines whose
   **first whitespace-separated token** equals exactly **`active`**
   (leading indentation is fine; `active-x`, `Active`, or `active2` do not
   count). Blank lines and `#` comment lines are skipped.
5. **Payload** — compute, using exact integer arithmetic and Python `%`
   semantics (result is always in `0 <= payload < P`; every feed has
   `P >= 1`):

   ```
   payload = (B * M + N) % P
   ```

## Deliverables (both required, under `/app`)

1. `/app/issue_token.py` — a self-contained Python program:

   ```
   python3 /app/issue_token.py <state_dir>
   ```

   It reads the four clue artifacts from the given state directory and
   prints the payload to **stdout** as a decimal integer followed by a
   newline (nothing else on stdout). It must work on **any** state directory
   following the layout above — the verifier runs it on hidden state
   directories with different values, comment decoys, duplicated keys/slots,
   indented roster lines, and negative integers — so do not hard-code the
   visible numbers.

2. `/app/answer.txt` — the payload **for the visible state directory
   `/app/state`**. It must contain exactly what the program prints when run
   as:

   ```
   python3 /app/issue_token.py /app/state > /app/answer.txt
   ```

   (a single decimal integer line).

## Sanity check

With the provided `/app/state`, the clues resolve to
`B = 137`, `M = 5`, `P = 97`, `N = 4`, so the payload is `10` — use this to
validate your reading of the rules, but your program must derive everything
from the files.

## Constraints

- No network access at run or verify time; standard library only.
- Do not read or modify `/tests` or `/solution`.
- Everything must be deterministic; integer arithmetic is exact.
