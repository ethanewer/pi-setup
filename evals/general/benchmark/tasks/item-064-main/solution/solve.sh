#!/bin/bash
set -euo pipefail

# Oracle for item-064-main: author a correct rules.json (regex-only engine),
# repair /app/moves.py with a correct self-contained legal-move generator, and
# run the pipeline to emit /app/output.json.

cat > /app/rules.json <<'JSON'
{"substitution":[{"id":"date_us","pattern":"\\b(?P<m>[0-9]{2})/(?P<d>[0-9]{2})/(?P<y>[0-9]{4})\\b","replace":"\\g<y>-\\g<m>-\\g<d>"},{"id":"date_eu","pattern":"\\b(?P<d2>[0-9]{2})\\.(?P<m2>[0-9]{2})\\.(?P<y2>[0-9]{4})\\b","replace":"\\g<y2>-\\g<m2>-\\g<d2>"}],"classification":[{"id":"ipv4_loose","pattern":"\\d{1,3}(?:\\.\\d{1,3}){3}","kind":"ipv4","verdict":"invalid"},{"id":"fen_like","pattern":"^[rnbqkpRNBQKP1-8]+(?:/[rnbqkpRNBQKP1-8]+){7}(?: [^ ]*){0,8}$","kind":"fen","verdict":"invalid"},{"id":"date_catch","pattern":"^[0-9]{4}-[0-9]{2}-[0-9]{2}$","kind":"date","verdict":"invalid"},{"id":"ipv4_valid","pattern":"^(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])(?:\\.(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])){3}$","kind":"ipv4","verdict":"valid"},{"id":"date_valid","pattern":"^(?:(?:(?:[0-9]{4})-(?:0[13578]|1[02])-(?:0[1-9]|[12]\\d|3[01])|(?:[0-9]{4})-(?:0[469]|11)-(?:0[1-9]|[12]\\d|30)|(?:[0-9]{4})-02-(?:0[1-9]|1\\d|2[0-8])|(?:[0-9]{2}(?:0[48]|[2468][048]|[13579][26])|(?:0[48]|[2468][048]|[13579][26])00)-02-29))$","kind":"date","verdict":"valid"},{"id":"fen_valid","pattern":"^[rnbqkpRNBQKP1-8]+(?:/[rnbqkpRNBQKP1-8]+){7} (?:w|b) (?:-|[KQkq]{1,4}) (?:-|[a-h][36]) (?:0|[1-9][0-9]*) [1-9][0-9]*$","kind":"fen","verdict":"valid"}]}
JSON

cat > /app/moves.py <<'PYEOF'
#!/usr/bin/env python3
"""Pure-python legal move generator -> sorted UCI list. No chess libraries."""

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


def attacked(board, pos, stm):
    """Is `pos` attacked by the opponent of the side to move?"""
    r, c = pos
    want = ('p', 'n', 'b', 'r', 'q', 'k') if stm == 'w' else ('P', 'N', 'B', 'R', 'Q', 'K')
    # pawns: opponent of white = black, black pawns move +row and attack (r-1, c-1),(r-1, c+1)
    prow = r - (1 if stm == 'w' else -1)
    for dc in (-1, 1):
        pr, pc = prow, c + dc
        if _inside(pr, pc) and board[pr][pc] == want[0]:
            return True
    for dr, dc in ((2,1),(2,-1),(-2,1),(-2,-1),(1,2),(1,-2),(-1,2),(-1,-2)):
        rr, cc = r+dr, c+dc
        if _inside(rr, cc) and board[rr][cc] == want[1]:
            return True
    for dr, dc in ((-1,-1),(-1,1),(1,-1),(1,1)):
        rr, cc = r+dr, c+dc
        while _inside(rr, cc):
            p = board[rr][cc]
            if p is not None:
                if p == want[2] or p == want[4]:
                    return True
                break
            rr += dr; cc += dc
    for dr, dc in ((-1,0),(1,0),(0,-1),(0,1)):
        rr, cc = r+dr, c+dc
        while _inside(rr, cc):
            p = board[rr][cc]
            if p is not None:
                if p == want[3] or p == want[4]:
                    return True
                break
            rr += dr; cc += dc
    for dr in (-1, 0, 1):
        for dc in (-1, 0, 1):
            if dr == 0 and dc == 0:
                continue
            rr, cc = r+dr, c+dc
            if _inside(rr, cc) and board[rr][cc] == want[5]:
                return True
    return False


def legal_moves(fen):
    board, stm, castle, ep = parse(fen)
    mine = 'PNBRQK' if stm == 'w' else 'pnbrqk'
    opp = 'pnbrqk' if stm == 'w' else 'PNBRQK'
    prom_rank = 0 if stm == 'w' else 7
    home_rank = 7 if stm == 'w' else 0
    start_rank = 6 if stm == 'w' else 1
    d = -1 if stm == 'w' else 1

    def sq(r, c):
        return FILES[c] + str(8 - r)

    # locate own + opponent kings
    own_king = None
    opp_king = None
    for r in range(8):
        for c in range(8):
            p = board[r][c]
            if p == ('K' if stm == 'w' else 'k'):
                own_king = (r, c)
            elif p == ('k' if stm == 'w' else 'K'):
                opp_king = (r, c)

    ep_sq = None
    if ep != '-':
        ep_sq = (8 - int(ep[1]), FILES.index(ep[0]))

    pseudo = []

    def add(fr, fc, tr, tc, promo=''):
        pseudo.append((fr, fc, tr, tc, promo))

    for r in range(8):
        for c in range(8):
            p = board[r][c]
            if not p or p not in mine:
                continue
            L = p.lower()
            if L == 'p':
                nr = r + d
                if _inside(nr, c) and board[nr][c] is None:
                    if nr == prom_rank:
                        for pr in ('QRBN' if stm=='w' else 'qrnb'):
                            add(r, c, nr, c, pr)
                    else:
                        add(r, c, nr, c)
                if r == start_rank and _inside(nr, c) and board[nr][c] is None:
                    rr = r + 2 * d
                    if _inside(rr, c) and board[nr][c] is None and board[rr][c] is None:
                        add(r, c, rr, c)
                for dc in (-1, 1):
                    nc = c + dc
                    if not _inside(nr, nc):
                        continue
                    t = board[nr][nc]
                    if t is not None and t in opp:
                        if nr == prom_rank:
                            for pr in ('QRBN' if stm=='w' else 'qrnb'):
                                add(r, c, nr, nc, pr)
                        else:
                            add(r, c, nr, nc)
                    elif t is None and ep_sq is not None and (nr, nc) == ep_sq:
                        # enemy pawn that double-pushed sits on same rank as us, adjacent col
                        if _inside(r, nc) and board[r][nc] in opp and board[r][nc].lower() == 'p':
                            # also must be the pawn that double-pushed from start rank
                            add(r, c, nr, nc)
            elif L == 'n':
                for dr, dc in ((2,1),(2,-1),(-2,1),(-2,-1),(1,2),(1,-2),(-1,2),(-1,-2)):
                    rr, cc = r+dr, c+dc
                    if _inside(rr, cc) and (board[rr][cc] is None or board[rr][cc] in opp):
                        add(r, c, rr, cc)
            elif L in ('b', 'q', 'r'):
                if L in ('b', 'q'):
                    for dr, dc in ((-1,-1),(-1,1),(1,-1),(1,1)):
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
                if L in ('r', 'q'):
                    for dr, dc in ((-1,0),(1,0),(0,-1),(0,1)):
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
                # castle
                if r == home_rank and c == 4:
                    if stm == 'w':
                        if 'K' in castle and board[7][5] is None and board[7][6] is None and board[7][7] == 'R':
                            if not any(attacked(board, (7, x), stm) for x in (4, 5, 6)):
                                add(7, 4, 7, 6)
                        if 'Q' in castle and board[7][3] is None and board[7][2] is None and board[7][1] is None and board[7][0] == 'R':
                            if not any(attacked(board, (7, x), stm) for x in (4, 3, 2)):
                                add(7, 4, 7, 2)
                    else:
                        if 'k' in castle and board[0][5] is None and board[0][6] is None and board[0][7] == 'r':
                            if not any(attacked(board, (0, x), stm) for x in (4, 5, 6)):
                                add(0, 4, 0, 6)
                        if 'q' in castle and board[0][3] is None and board[0][2] is None and board[0][1] is None and board[0][0] == 'r':
                            if not any(attacked(board, (0, x), stm) for x in (4, 3, 2)):
                                add(0, 4, 0, 2)

    # filter legality: simulate each candidate, then confirm own king not attacked
    result = set()

    def apply_and_attack(m):
        fr, fc, tr, tc, promo = m
        nb = [row[:] for row in board]
        moving = nb[fr][fc]
        captured = nb[tr][tc]
        nb[tr][tc] = promo if promo else moving
        nb[fr][fc] = None
        if moving.lower() == 'p' and abs(tc - fc) == 1 and abs(tr - fr) == 1 and captured is None:
            # en passant capture: pawn removed
            nb[fr][tc] = None
        if moving.lower() == 'k' and abs(tc - fc) == 2:
            if tc == 6:
                nb[fr][5] = nb[fr][7]
                nb[fr][7] = None
            else:
                nb[fr][3] = nb[fr][0]
                nb[fr][0] = None
        # locate own king in nb
        kp = None
        for rr in range(8):
            for cc in range(8):
                if nb[rr][cc] == ('K' if stm == 'w' else 'k'):
                    kp = (rr, cc)
        if kp is None:
            return True  # no king: keep move (degenerate but not attacked)
        return not attacked(nb, kp, stm)

    for m in pseudo:
        if apply_and_attack(m):
            fr, fc, tr, tc, promo = m
            result.add(sq(fr, fc) + sq(tr, tc) + (promo or '').lower())
    return sorted(result)


if __name__ == '__main__':
    import sys
    fen = sys.argv[1]
    print('\n'.join(legal_moves(fen)))
PYEOF

# Generate the output.
(cd /app && python3 run.py)
echo "solve.sh ran to completion"