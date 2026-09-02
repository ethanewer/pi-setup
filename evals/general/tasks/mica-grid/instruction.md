# Mica-Grid puzzle wire — exact sudoku solver CLI

The **Mica-Grid** puzzle wire feeds standard 9x9 sudoku boards to a typesetting
frontend. You must implement the wire's solver as a small command-line program
and run it once on the provided board. The solver must apply an exact method
(constraint propagation and/or backtracking) so that **every** board it accepts
is filled completely and correctly — each row, column, and 3x3 box contains
the digits 1–9 exactly once.

Everything runs in `/app` with Python 3.12 **standard library only**. No
network.

## Board file format

A board file is UTF-8 text with exactly **9 board lines**:

- Each board line has exactly **9 characters**: digits `1`–`9` for given
  cells, and `0` or `.` for empty cells (both must be accepted).
- Tolerate and ignore: surrounding whitespace on each line, CRLF line endings,
  and blank lines after the 9th board line (e.g. a trailing newline).
- Anything else is **malformed**: fewer or more than 9 board lines, a line
  with the wrong length, or any character outside `1234567890.` and
  whitespace.

## Deliverables

1. **`/app/sudoku.py`** — the solver CLI:

   ```
   python3 /app/sudoku.py <board_file> <output_file>
   ```

   Behavior and exit codes (part of the contract):

   - **Solvable board** → write the completed board to `<output_file>` as 9
     lines of exactly 9 digits `1`–`9` each, a trailing newline after the last
     line, and exit with status **0**. The completion must preserve every
     given and be the (unique) valid solution of the puzzle.
   - **Well-formed but unsolvable board** → exit with status **1** and write
     nothing (or nothing meaningful) to the output file. Never hang: a
     contradiction must be detected by the search.
   - **Malformed board** (see format above) → exit with status **2**, print a
     diagnostic to stderr, and write nothing to the output file.
   - Missing arguments or an unreadable board file must also exit non-zero
     with a diagnostic on stderr (never an unhandled traceback dump as the
     only output is fine to accompany a non-zero exit, but the exit status
     must be non-zero and the output file must not contain a bogus board).

   The solver must be fast and deterministic: hidden boards solve in well
   under a second each with a plain backtracking search plus basic
   constraint propagation.

2. **`/app/solved.txt`** — the output produced by running your solver on the
   provided board:

   ```
   python3 /app/sudoku.py /app/puzzle.txt /app/solved.txt
   ```

## Provided fixture (do not modify)

- `/app/puzzle.txt` — the shipped 9x9 board in the format above. Its exact
  original bytes are checksum-verified; do not edit it.

## What the checker enforces

- Runs `/app/sudoku.py` on `/app/puzzle.txt` and on every hidden board under
  `/tests/hidden`, and requires the exit code and (for solvable boards) the
  written output to match exactly: 9 lines of digits, correct completion
  (rows, columns and 3x3 boxes all contain 1–9), all givens preserved, and
  equality with the reference solution of the puzzle.
- Solvable hidden boards include a sparse board (~33 givens), a nearly
  complete board (3 empty cells), and the shipped board.
- One hidden board is **well-formed but unsolvable** → your program must exit
  with status 1.
- Two hidden boards are **malformed** (only 8 board lines; a board containing
  an `x` character) → your program must exit with status 2.
- `/app/solved.txt` must equal the reference solution of `/app/puzzle.txt`
  byte-for-byte (modulo a single trailing newline).

An incomplete fill, a board violating the row/column/box rule, changed givens,
or a wrong exit code on the unsolvable/malformed probes fails the check.

## Constraints

- Do not modify `/app/puzzle.txt`.
- Standard library only; deterministic; no network; no third-party packages.
