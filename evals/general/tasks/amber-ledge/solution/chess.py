#!/usr/bin/env python3
"""Libra-core chess legal move generator (clean-room implementation).

Computes the exact set of legal moves in a position (FEN-style notation)
including castling, en-passant, and promotions, and identifies the moves
that deliver immediate checkmate (mate-in-one).

CLI:
  python3 chess.py legal "<fen>"   -> JSON array of legal UCI-style moves
  python3 chess.py mate  "<fen>"   -> JSON array of mate-in-one moves
"""
import sys

FILES = "abcdefgh"

def sq(r, c):
    return FILES[c] + str(8 - r)

def coords(s):
    return (8 - int(s[1]), FILES.index(s[0]))

def in_board(r, c):
    return 0 <= r <= 7 and 0 <= c <= 7

def opp(side):
    return 'b' if side == 'w' else 'w'

def is_own(pc, side):
    return pc.isupper() if side == 'w' else pc.islower()

def is_enemy(pc, side):
    return (pc.islower() if side == 'w' else pc.isupper())

SN = sq

class Pos:
    """board: dict square->piece char (white uppercase). color = side to move."""
    __slots__ = ('board', 'color', 'castle', 'ep')

    def __init__(self, board=None, color='w', castle='-', ep=None):
        self.board = board if board is not None else {}
        self.color = color
        self.castle = castle
        self.ep = ep

    def copy(self):
        return Pos(dict(self.board), self.color, self.castle, self.ep)


def parse_fen(fen):
    parts = fen.split()
    place = parts[0]
    color = 'w' if parts[1] == 'w' else 'b'
    castle = parts[2] if len(parts) > 2 else '-'
    ep = parts[3] if len(parts) > 3 and parts[3] != '-' else None
    board = {}
    for r, row in enumerate(place.split('/')):
        c = 0
        for ch in row:
            if ch.isdigit():
                c += int(ch)
            else:
                board[sq(r, c)] = ch
                c += 1
    return Pos(board, color, castle, ep)


def find_king(board, side):
    k = 'K' if side == 'w' else 'k'
    for s, p in board.items():
        if p == k:
            return coords(s)
    return None


def attacked(board, r, c, by):
    """Return True if square (r,c) is attacked by a piece of side `by`."""
    # pawns
    if by == 'w':
        for dr in (1,):
            for dc in (-1, 1):
                nr, nc = r + dr, c + dc
                if in_board(nr, nc) and board.get(sq(nr, nc)) == 'P':
                    return True
    else:
        for dr in (-1,):
            for dc in (-1, 1):
                nr, nc = r + dr, c + dc
                if in_board(nr, nc) and board.get(sq(nr, nc)) == 'p':
                    return True
    # knights
    for dr, dc in ((-2,-1),(-2,1),(2,-1),(2,1),(-1,-2),(-1,2),(1,-2),(1,2)):
        nr, nc = r + dr, c + dc
        if in_board(nr, nc):
            pc = board.get(sq(nr, nc))
            if pc is not None and pc in 'Nn' and is_own(pc, by):
                return True
    # orthogonals (rook/queen/king)
    for dr, dc in ((-1,0),(1,0),(0,-1),(0,1)):
        nr, nc = r + dr, c + dc
        step = 0
        while in_board(nr, nc):
            pc = board.get(sq(nr, nc))
            if pc is not None:
                if (pc in 'RrQq' or (pc in 'Kk' and step == 0)) and is_own(pc, by):
                    return True
                break
            step += 1
            nr += dr; nc += dc
    # diagonals (bishop/queen/king)
    for dr, dc in ((-1,-1),(-1,1),(1,-1),(1,1)):
        nr, nc = r + dr, c + dc
        step = 0
        while in_board(nr, nc):
            pc = board.get(sq(nr, nc))
            if pc is not None:
                if (pc in 'BbQq' or (pc in 'Kk' and step == 0)) and is_own(pc, by):
                    return True
                break
            step += 1
            nr += dr; nc += dc
    return False


def in_check(pos, side):
    kc = find_king(pos.board, side)
    if kc is None:
        return False
    return attacked(pos.board, kc[0], kc[1], opp(side))


def apply_move(board, m):
    fr, to = m['fr'], m['to']
    board[to] = board[fr]
    del board[fr]
    if m.get('castle'):
        if to == 'g1':
            board['f1'] = board['h1']; del board['h1']
        elif to == 'c1':
            board['d1'] = board['a1']; del board['a1']
        elif to == 'g8':
            board['f8'] = board['h8']; del board['h8']
        elif to == 'c8':
            board['d8'] = board['a8']; del board['a8']
    if m.get('ep'):
        cap = to[0] + fr[1]
        board.pop(cap, None)
    if m.get('promo'):
        board[to] = m['promo']


def move_leaves(m, pos):
    """True if after applying the move the mover's own king IS attacked.
    A legal move never leaves its side in check, so legality = not move_leaves."""
    b = pos.board.copy()
    apply_move(b, m)
    return in_check(Pos(b, pos.color), pos.color)


def move_ok(m, pos):
    """Legal if the mover's king is not attacked after the move."""
    b = pos.board.copy()
    apply_move(b, m)
    return not in_check(Pos(b, pos.color), pos.color)


def gene_pseudo(pos):
    """Generate pseudo-legal moves as dicts {fr,to[,promo][,castle][,ep]}."""
    side = pos.color
    moves = []
    for s, pc in pos.board.items():
        if not is_own(pc, side):
            continue
        r, c = coords(s)
        typ = pc.upper()

        if typ == 'P':
            d = -1 if side == 'w' else 1
            start_r = 6 if side == 'w' else 1
            promo_r = 0 if side == 'w' else 7
            nr = r + d
            # forward push
            if in_board(nr, c) and sq(nr, c) not in pos.board:
                if nr == promo_r:
                    for pr in ('Q', 'R', 'B', 'N'):
                        moves.append({'fr': s, 'to': sq(nr, c), 'promo': pr})
                else:
                    moves.append({'fr': s, 'to': sq(nr, c)})
                    if r == start_r:
                        nr2 = r + 2 * d
                        if sq(nr2, c) not in pos.board:
                            moves.append({'fr': s, 'to': sq(nr2, c)})
            # captures (diagonal)
            for dc in (-1, 1):
                nc = c + dc
                if not in_board(nr, nc):
                    continue
                ts = sq(nr, nc)
                tp = pos.board.get(ts)
                if tp is not None and is_enemy(tp, side):
                    if nr == promo_r:
                        for pr in ('Q', 'R', 'B', 'N'):
                            moves.append({'fr': s, 'to': ts, 'promo': pr})
                    else:
                        moves.append({'fr': s, 'to': ts})
                elif pos.ep and ts == pos.ep:
                    moves.append({'fr': s, 'to': ts, 'ep': True})

        elif typ == 'N':
            for dr, dc in ((-2,-1),(-2,1),(2,-1),(2,1),(-1,-2),(-1,2),(1,-2),(1,2)):
                nr, nc = r + dr, c + dc
                if in_board(nr, nc):
                    ts = sq(nr, nc)
                    tp = pos.board.get(ts)
                    if tp is None or is_enemy(tp, side):
                        moves.append({'fr': s, 'to': ts})

        elif typ in ('B', 'R', 'Q'):
            dirs = ((-1,-1),(-1,1),(1,-1),(1,1)) if typ == 'B' else (
                ((-1,-1),(-1,1),(1,-1),(1,1),(-1,0),(1,0),(0,-1),(0,1)) if typ == 'Q'
                else ((-1,0),(1,0),(0,-1),(0,1)))
            for dr, dc in dirs:
                nr, nc = r + dr, c + dc
                while in_board(nr, nc):
                    ts = sq(nr, nc)
                    tp = pos.board.get(ts)
                    if tp is None:
                        moves.append({'fr': s, 'to': ts})
                    else:
                        if is_enemy(tp, side):
                            moves.append({'fr': s, 'to': ts})
                        break
                    nr += dr; nc += dc

        elif typ == 'K':
            for dr, dc in ((-1,-1),(-1,1),(1,-1),(1,1),(-1,0),(1,0),(0,-1),(0,1)):
                nr, nc = r + dr, c + dc
                if in_board(nr, nc):
                    ts = sq(nr, nc)
                    tp = pos.board.get(ts)
                    if tp is None or is_enemy(tp, side):
                        moves.append({'fr': s, 'to': ts})
            # castling
            home_r = 7 if side == 'w' else 0
            if r == home_r and c == 4 and not in_check(pos, side):
                if side == 'w':
                    if 'K' in pos.castle and pos.board.get('h1') == 'R' \
                       and pos.board.get('f1') is None and pos.board.get('g1') is None \
                       and not attacked(pos.board, home_r, 5, opp(side)) \
                       and not attacked(pos.board, home_r, 6, opp(side)):
                        moves.append({'fr': s, 'to': sq(home_r, 6), 'castle': True})
                    if 'Q' in pos.castle and pos.board.get('a1') == 'R' \
                       and pos.board.get('b1') is None and pos.board.get('c1') is None \
                       and pos.board.get('d1') is None \
                       and not attacked(pos.board, home_r, 3, opp(side)) \
                       and not attacked(pos.board, home_r, 2, opp(side)):
                        moves.append({'fr': s, 'to': sq(home_r, 2), 'castle': True})
                else:
                    if 'k' in pos.castle and pos.board.get('h8') == 'r' \
                       and pos.board.get('f8') is None and pos.board.get('g8') is None \
                       and not attacked(pos.board, home_r, 5, opp(side)) \
                       and not attacked(pos.board, home_r, 6, opp(side)):
                        moves.append({'fr': s, 'to': sq(home_r, 6), 'castle': True})
                    if 'q' in pos.castle and pos.board.get('a8') == 'r' \
                       and pos.board.get('b8') is None and pos.board.get('c8') is None \
                       and pos.board.get('d8') is None \
                       and not attacked(pos.board, home_r, 3, opp(side)) \
                       and not attacked(pos.board, home_r, 2, opp(side)):
                        moves.append({'fr': s, 'to': sq(home_r, 2), 'castle': True})
    return moves


def legal_moves(fen):
    pos = parse_fen(fen)
    out = []
    for m in gene_pseudo(pos):
        if move_leaves(m, pos):
            continue
        s = m['fr'] + m['to'] + (m['promo'].lower() if m.get('promo') else '')
        out.append(s)
    return sorted(out)


def legal_pseudo(pos):
    return [m for m in gene_pseudo(pos) if not move_leaves(m, pos)]


def mate_moves(fen):
    pos = parse_fen(fen)
    out = []
    for m in gene_pseudo(pos):
        if move_leaves(m, pos):
            continue
        b = pos.board.copy()
        apply_move(b, m)
        npos = Pos(b, opp(pos.color), '-', None)
        if not in_check(npos, npos.color):
            continue
        # must be checkmate: opponent has no legal reply
        mated = True
        for r in gene_pseudo(npos):
            if not move_leaves(r, npos):
                mated = False
                break
        if mated:
            out.append(m['fr'] + m['to'] + (m['promo'].lower() if m.get('promo') else ''))
    return sorted(out)


if __name__ == '__main__':
    cmd = sys.argv[1]
    fen = sys.argv[2]
    res = legal_moves(fen) if cmd == 'legal' else mate_moves(fen)
    print(__import__('json').dumps(res))