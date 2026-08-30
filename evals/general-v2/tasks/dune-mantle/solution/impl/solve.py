#!/usr/bin/python3
"""dune-mantle dossier solver.

Three independent integer sub-problems reachable through one CLI:

    solve.py wcnf <file>   weighted-MAX-SAT optimum on a .wcnf instance
    solve.py qfbv          reads a QF_BV SMT-LIB script on stdin, prints sat/unsat
    solve.py seats <file>  seating CSP: legal board strings + spelled fixed point

The wcnf parser tolerates comment/blank/'%' lines and a `top` weight token for
hard clauses (== sum of soft weights + 1).  Objective: sum of weights of
satisfied soft clauses while every hard clause is satisfied.
"""
import sys, re, itertools
from z3 import *

# ---------------------------------------------------------------- WCNF / MAX-SAT
def solve_wcnf(path):
    var_ids = {}
    hards = []
    softs = []          # (weight, [lits])
    raw = []

    for ln in open(path):
        ln = ln.strip()
        if not ln or ln.startswith('c') or ln == '%':
            continue
        if ln.startswith('p '):
            continue
        raw.append(ln.split())

    top = sum(int(t[0]) for t in raw if t[0] != 'top') + 1

    for t in raw:
        lits = [int(x) for x in t[1:-1]]
        if t[0] == 'top':
            hards.append(lits)
        else:
            softs.append((int(t[0]), lits))

    def var(a):
        a = abs(a)
        if a not in var_ids:
            var_ids[a] = Bool('v%d' % a)
        return var_ids[a]

    def lit(b):
        return var(b) if b > 0 else Not(var(-b))

    var_ids = {}
    opt = Optimize()
    inds = []
    for lits in hards:
        opt.add(Or([lit(l) for l in lits]))
    for (w, lits) in softs:
        b = Bool('ind_%d' % len(inds))
        inds.append((b, w))
        opt.add(Implies(b, Or([lit(l) for l in lits])))
        opt.maximize(If(b, w, 0))
    if opt.check() != sat:
        return None
    m = opt.model()
    total = 0
    for (b, w) in inds:
        if m.eval(b, model_completion=True):
            total += w
    assign = {str(i): str(m.eval(v, model_completion=True))
              for i, v in var_ids.items()}
    return total, assign


# ------------------------------------------------------------------------- QF_BV
def solve_qfbv():
    src = sys.stdin.read()
    t2 = re.sub(r'\(check-sat\)', '', src)
    t2 = re.sub(r'\(get-model\)', '', t2)
    t2 = re.sub(r'\(exit\)', '', t2)
    t2 = re.sub(r'\(set-logic\s+[^)]*\)', '', t2)
    t2 = re.sub(r'\(set-option\s+[^)]*\)', '', t2)
    s = Solver()
    try:
        for a in parse_smt2_string(t2):
            s.add(a)
    except Exception:
        sys.stdout.write('unknown\n')
        return
    r = s.check()
    if r == sat:
        sys.stdout.write('sat\n')
    elif r == unsat:
        sys.stdout.write('unsat\n')
    else:
        sys.stdout.write('unknown\n')


# ----------------------------------------------------------------- SEATING CSP
def seats_file(path):
    people = []
    focus = None
    allies = set()
    enemies = set()
    for ln in open(path):
        ln = ln.split('#')[0].strip()
        if not ln:
            continue
        kk, _, vv = ln.partition(':')
        v = vv.strip()
        kk = kk.strip()
        if kk == 'people':
            people = [x.strip() for x in v.split(',') if x.strip()]
        elif kk == 'focus':
            focus = v
        elif kk == 'allies':
            for ab in v.split(','):
                ab = ab.strip()
                if len(ab) == 3 and ab[1] == '-':
                    allies.add(frozenset((ab[0], ab[2])))
        elif kk == 'enemies':
            for ab in v.split(','):
                ab = ab.strip()
                if len(ab) == 3 and ab[1] == '-':
                    enemies.add(frozenset((ab[0], ab[2])))
    return people, focus, allies, enemies


def legal(seq, people, focus, allies, enemies):
    n = len(people)
    for i in range(n):
        if frozenset((seq[i], seq[(i + 1) % n])) in enemies:
            return False
    for i in range(n):
        nb = {seq[(i - 1) % n], seq[(i + 1) % n]}
        if not any(frozenset((seq[i], q)) in allies for q in nb):
            return False
    fj = seq.index(focus)
    nb = {seq[(fj - 1) % n], seq[(fj + 1) % n]}
    return all(frozenset((focus, q)) in allies for q in nb) and len(nb) == 2


def spell(n):
    ones = {0:'zero',1:'one',2:'two',3:'three',4:'four',5:'five',6:'six',7:'seven',
            8:'eight',9:'nine',10:'ten',11:'eleven',12:'twelve',13:'thirteen',
            14:'fourteen',15:'fifteen',16:'sixteen',17:'seventeen',18:'eighteen',19:'nineteen'}
    tens = {2:'twenty',3:'thirty',4:'forty',5:'fifty',6:'sixty',7:'seventy',8:'eighty',9:'ninety'}
    if n < 20:
        return ones[n]
    if n < 1000:
        o, d = n % 10, n // 10
        if d < 10:
            return tens[d] + ('' if o == 0 else '-' + ones[o])
    # generic fallback
    return ones.get(n, str(n))


def count_letters(n):
    return len([c for c in spell(n) if c.isalpha()])


def fixed_point(k):
    n = k
    steps = 0
    while True:
        c = count_letters(n)
        steps += 1
        if c == n:
            break
        n = c
    return n, spell(n).replace('-', '').replace(' ', ''), steps


def solve_seats(path):
    people, focus, allies, enemies = seats_file(path)
    boards = set()
    for perm in itertools.permutations(people):
        if perm[0] != focus:
            continue
        if legal(perm, people, focus, allies, enemies):
            boards.add(''.join(perm))
    boards = sorted(boards)
    n = len(people)
    pairs = set()
    for b in boards:
        i = b.index(focus)
        pairs.add(b[(i - 1) % n])
        pairs.add(b[(i + 1) % n])
    k = len(boards)
    fixval, phrase, steps = fixed_point(k)
    return focus, sorted(pairs), boards, fixval, phrase, steps


# --------------------------------------------------------------------------
def main():
    if len(sys.argv) < 2:
        sys.stderr.write("usage: solve.py wcnf|qfbv|seats ...\n")
        sys.exit(1)
    cmd = sys.argv[1]
    if cmd == 'wcnf':
        val = solve_wcnf(sys.argv[2])
        sys.stdout.write('OPT %s\n' % (val[0] if val else 'UNSAT'))
    elif cmd == 'qfbv':
        solve_qfbv()
    elif cmd == 'seats':
        focus, pairs, boards, fixval, phrase, steps = solve_seats(sys.argv[2])
        sys.stdout.write('FOCUS %s\n' % focus)
        sys.stdout.write('PAIRS %s\n' % ','.join(pairs))
        sys.stdout.write('NBOARDS %d\n' % len(boards))
        for b in boards:
            sys.stdout.write('%s\n' % b)
        sys.stdout.write('FIXPOINT %d\n' % fixval)
        sys.stdout.write('PHRASE %s\n' % phrase)
        sys.stdout.write('STEPS %d\n' % steps)
    else:
        sys.stderr.write("unknown subcommand\n")
        sys.exit(1)


if __name__ == '__main__':
    main()