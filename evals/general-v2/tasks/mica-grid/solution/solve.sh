#!/bin/bash
# Real oracle for mica-grid: writes the /app/sudoku.py deliverable (an exact
# backtracking sudoku solver CLI with the 0/1/2 exit-code contract), then RUNS
# it on /app/puzzle.txt to produce /app/solved.txt. Never reads /tests.
set -eu
mkdir -p /app

cat > /app/sudoku.py <<'PY'
#!/usr/bin/env python3
"""Mica-Grid exact 9x9 sudoku solver CLI.

Usage: python3 sudoku.py <board_file> <output_file>
Exit codes: 0 solved (output written), 1 well-formed but unsolvable,
2 malformed board / bad invocation.
"""
import sys

DIGITS = set('123456789')
EMPTY = set('0.')


class Malformed(Exception):
    pass


def read_board(path):
    try:
        with open(path, 'r', encoding='utf-8', errors='strict') as fh:
            text = fh.read()
    except OSError:
        raise Malformed('cannot read board file')
    lines = [ln.rstrip('\r\n') for ln in text.split('\n')]
    while lines and lines[-1].strip() == '':
        lines.pop()
    if len(lines) != 9:
        raise Malformed('expected 9 board lines, found %d' % len(lines))
    board = []
    for ln in lines:
        if len(ln.strip()) != 9 or len(ln) != len(ln.strip()):
            stripped = ln.strip()
            if len(stripped) != 9:
                raise Malformed('board line has %d characters' % len(stripped))
            ln = stripped
        row = []
        for ch in ln:
            if ch in DIGITS:
                row.append(ch)
            elif ch in EMPTY:
                row.append(0)
            elif ch in ' \t':
                raise Malformed('internal whitespace in board line')
            else:
                raise Malformed('invalid character %r' % ch)
        board.append(row)
    return board


def candidates(board, r, c):
    used = set(board[r])
    used.update(board[i][c] for i in range(9))
    br, bc = 3 * (r // 3), 3 * (c // 3)
    for i in range(br, br + 3):
        for j in range(bc, bc + 3):
            used.add(board[i][j])
    return DIGITS - used


def solve(board):
    # constraint propagation + minimum-remaining-values backtracking
    def find_best_cell():
        best = None
        for r in range(9):
            for c in range(9):
                if board[r][c] == 0:
                    cand = candidates(board, r, c)
                    n = len(cand)
                    if n == 0:
                        return (r, c, cand)
                    if best is None or n < len(best[2]):
                        best = (r, c, cand)
                        if n == 1:
                            return best
        return best

    cell = find_best_cell()
    if cell is None:
        return True  # full board
    r, c, cand = cell
    if not cand:
        return False
    for d in sorted(cand):
        board[r][c] = d
        if solve(board):
            return True
        board[r][c] = 0
    return False


def main():
    if len(sys.argv) != 3:
        sys.stderr.write('usage: sudoku.py <board_file> <output_file>\n')
        sys.exit(2)
    try:
        board = read_board(sys.argv[1])
    except Malformed as exc:
        sys.stderr.write('malformed board: %s\n' % exc)
        sys.exit(2)
    if not solve(board):
        sys.stderr.write('board is not solvable\n')
        sys.exit(1)
    with open(sys.argv[2], 'w', encoding='utf-8') as fh:
        for row in board:
            fh.write(''.join(str(v) for v in row) + '\n')
    sys.exit(0)


if __name__ == '__main__':
    main()
PY

chmod +x /app/sudoku.py

python3 /app/sudoku.py /app/puzzle.txt /app/solved.txt
echo "exit=$?"

echo "solve.sh done"
cat /app/solved.txt
