#!/usr/bin/env python3
"""LEGAL MOVE GENERATOR - THIS COPY IS INCOMPLETE / BUGGY.

The required reduce delivers legal moves in UCI notation (sorted list of
strings).  This stub generates *some* moves but is missing required chess
behaviour.  Repair /app/moves.py so that `legal_moves(fen)` returns the full,
correct, sorted list of legal moves (UCI) for any FEN string.

Known gaps in this file (you must fix them):
  1. Castling moves are not generated at all.
  2. En-passant captures are not generated.
  3. Pawn promotion is not generated (promotion suffix is dropped).
  4. There is NO legality filter: moves that would leave your own king in
     check are still returned, and your king/rook can move into check.
"""

FILES = 'abcdefgh'


def parse(fen):
    parts = fen.split()
    rows = parts[0].split('/')
    board = [[None] * 8 for _ in range(8)]
    for r, row in enumerate(rows):
        c = 0
        for ch in row:
            if ch.isdigit():
                c += int(ch)
            else:
                board[r][c] = ch
                c += 1
    stm = parts[1]
    castle = parts[2] if len(parts) > 2 else '-'
    ep = parts[3] if len(parts) > 3 else '-'
    return board, stm, castle, ep


def _inside(r, c):
    return 0 <= r < 8 and 0 <= c < 8


def legal_moves(fen):
    board, stm, _castle, _ep = parse(fen)
    mine = 'PNBRQK' if stm == 'w' else 'pnbrqk'
    opp = 'pnbrqk' if stm == 'w' else 'PNBRQK'
    prom_rank = 0 if stm == 'w' else 7
    d = -1 if stm == 'w' else 1
    start_rank = 6 if stm == 'w' else 1
    moves = set()

    def sq(r, c):
        return FILES[c] + str(8 - r)

    def add(fr, fc, tr, tc, promo=''):
        moves.add(sq(fr, fc) + sq(tr, tc) + promo)

    for r in range(8):
        for c in range(8):
            p = board[r][c]
            if not p or p not in mine:
                continue
            L = p.lower()
            if L == 'p':
                nr = r + d
                if _inside(nr, c) and board[nr][c] is None:
                    add(r, c, nr, c)  # single push (no promotion)
                    rr = r + 2 * d
                    if r == start_rank and _inside(rr, c) and board[nr][c] is None and board[rr][c] is None:
                        add(r, c, rr, c)
                for dc in (-1, 1):
                    nc = c + dc
                    if _inside(nr, nc) and board[nr][nc] in opp:
                        add(r, c, nr, nc)  # capture (no promotion)
                    # (en passant intentionally missing)
            elif L == 'n':
                for dr, dc in ((2,1),(2,-1),(-2,1),(-2,-1),(1,2),(1,-2),(-1,2),(-1,-2)):
                    rr, cc = r+dr, c+dc
                    if _inside(rr, cc) and (board[rr][cc] is None or board[rr][cc] in opp):
                        add(r, c, rr, cc)
            elif L in ('b', 'q', 'r'):
                dirs = ((-1,-1),(-1,1),(1,-1),(1,1)) if L in ('b', 'q') else ()
                dirs = dirs + ((-1,0),(1,0),(0,-1),(0,1)) if L in ('r', 'q') else dirs
                for dr, dc in dirs:
                    rr, cc = r+dr, c+dc
                    while _inside(rr, cc):
                        t = board[rr][cc]
                        if t is None:
                            add(r, c, rr, cc)
                        else:
                            if t in opp:
                                add(r, c, rr, cc)
                            break
                        rr += dr; cc += dc
            elif L == 'k':
                for dr in (-1, 0, 1):
                    for dc in (-1, 0, 1):
                        if dr == 0 and dc == 0:
                            continue
                        rr, cc = r+dr, c+dc
                        if _inside(rr, cc) and (board[rr][cc] is None or board[rr][cc] in opp):
                            add(r, c, rr, cc)
                # (castling intentionally missing)
    return sorted(moves)


if __name__ == '__main__':
    import sys
    print('\n'.join(legal_moves(sys.argv[1])))