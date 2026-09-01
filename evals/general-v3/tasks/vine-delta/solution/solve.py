#!/usr/bin/env python3
"""
vine-delta arcade-solver.

A single module implementing the five arbiter stations of the Vine-Delta board
described in instruction.md:

  - max_quiet_gap(cycles)      scheduling quiet-gap computation
  - weighted_return(w, v)      weighted-return dot product
  - solve_sudoku(board)        9x9 sudoku exact completion
  - play(sock)                 turn-based lane strategy entrypoint
  - gen_moves()                replay a canonical lane session -> /app/moves.txt

Only the Python standard library is required. Every function is pure and has a
documented, deterministic contract (see instruction.md); `play` also writes
exactly one token per turn through the supplied socket-like object.
"""

import math


def max_quiet_gap(cycles):
    """
    Three periodic event schedules. Schedule i fires on day index d (d = 0,1,2,...)
    whenever d % cycles[i] == 0, for each of the (normally three) cycle lengths.

    A day that no schedule fires on is a "silent" day. Because the three
    schedules jointly repeat every L = lcm(a, b, c) days, the largest run of
    consecutive silent days between two firing days equals the maximum run within
    the periodic block [0, L]. day 0 and day L both fire (L % * == 0).

    Returns the maximum gap (an int >= 0) between consecutive firing days.
    cycles: iterable of positive integers. Raises on non-positive values.
    """
    cs = [int(c) for c in cycles]
    for c in cs:
        if c <= 0:
            raise ValueError("cycle lengths must be positive integers")
    a, b, c = cs[0], cs[1], cs[2]
    L = math.lcm(a, b, c)
    last_fire = 0          # day 0 fires (divisible by all c)
    best = 0
    for d in range(1, L + 1):          # day L fires too
        if d % a == 0 or d % b == 0 or d % c == 0:
            gap = d - last_fire - 1
            if gap > best:
                best = gap
            last_fire = d
    return best


def weighted_return(weights, values):
    """Weighted-return dot product  sum_i w_i * v_i.

    Returns a Python float. Raises ValueError if the two vectors differ in
    length (that is an explicit malformed input). Empty equal-length vectors
    yield 0.0.
    """
    if len(weights) != len(values):
        raise ValueError("weight and value vectors must have equal length")
    total = 0.0
    for w, v in zip(weights, values):
        total += float(w) * float(v)
    return total


def _row_ok(board, r, c, candidate):
    for i in range(9):
        if candidate == board[r][i] or candidate == board[i][c]:
            return False
    br, bc = 3 * (r // 3), 3 * (c // 3)
    for i in range(3):
        for j in range(3):
            if candidate == board[br + i][bc + j]:
                return False
    return True


def _fill(board):
    for r in range(9):
        for c in range(9):
            if board[r][c] == 0:
                for candidate in range(1, 10):
                    if _row_ok(board, r, c, candidate):
                        board[r][c] = candidate
                        if _fill(board):
                            return True
                        board[r][c] = 0
                return False
    return True


def solve_sudoku(board):
    """Solve a standard 9x9 Sudoku grid in place and return it.

    Accepts a board shaped 9 rows x 9 columns (each value an int in
    0..9, where 0 marks an empty cell). Mutates and returns the same
    structure fully completed with digits 1..9 so that every row, column
    and 3x3 box contains distinct digits.

    Raises ValueError if the grid is not exactly 9x9 (rows of length 9,
    exactly 9 rows). A puzzle with no completion raises ValueError too.
    """
    if len(board) != 9 or any(len(row) != 9 for row in board):
        raise ValueError("sudoku grid must be exactly 9x9")
    g = [list(row) for row in board]
    if not _fill(g):
        raise ValueError("puzzle has no valid completion")
    for r in range(9):
        board[r] = g[r]
    return board


def _respond(line):
    """Turn one lane descriptor into the strategy's one reply token."""
    try:
        parts = line.split()
        n = int(parts[0])
        cells = parts[1]
        pos = int(parts[2])
        if len(cells) != n:
            raise ValueError("lane length mismatch")
        legal = [i for i in range(n) if i != pos and cells[i] == '.']
        if legal:
            return str(legal[0])
        return "-1"          # hold marker: no legal open cell available
    except Exception:
        return "ERR"         # malformed descriptor margin marker


def play(sock):
    """Strategy entrypoint with the exact signature play(sock).

    Consumes one lane descriptor (`n cells pos`) per turn from ``sock.recv()``
    until EOF (empty string), and replies exactly one token per turn via
    ``sock.sendall(...)``:
      - a lane-index i with 0<=i<n, i != pos and cells[i]=='.' (a legal move,
        the lowest such index), or
      - "-1" when no legal move exists this turn, or
      - "ERR" when the descriptor is malformed.
    """
    while True:
        line = sock.recv()
        if not line:
            break
        sock.sendall(_respond(line) + "\n")


# Canonical lane session used to produce /app/moves.txt (see instruction.md).
# Each entry is a descriptor string; replies are generated by the SAME strategy
# logic as `play`, so /app/moves.txt documents one legal replay per turn.
SESSION = [
    "3 ... 0",
    "3 ... 1",
    "3 .#. 0",
    "4 .#.. 2",
    "5 ..#.. 1",
    "2 ## 0",
    "6 .#.#.. 3",
    "1 . 0",
]


def gen_moves():
    """Regenerate the canonical replay. Returns a single string filename-free."""
    return "\n".join(_respond(ln) for ln in SESSION) + "\n"


def self_check():
    """Sanity checks to catch authoring mistakes (not used by the verifier)."""
    assert max_quiet_gap([2, 3, 5]) == 1
    assert weighted_return_ok() == True


def weighted_return_ok():
    return abs(weighted_return([0.5, -1.0, 2.0], [2.0, 3.0, 1.0]) - 0.0) < 1e-9


if __name__ == "__main__":
    import sys, os
    if "--gen-moves" in sys.argv:
        with open("/app/moves.txt", "w") as fh:
            fh.write(gen_moves())
        sys.exit(0)
    sys.stdout.write("vine-delta solver module ready\n")