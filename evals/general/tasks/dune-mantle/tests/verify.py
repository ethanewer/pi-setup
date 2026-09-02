#!/usr/bin/env python3
"""dune-mantle verifier. Independent recomputation of every hidden boundary.

Runs the agent's /app/solve.py and the globally-invocable `symxe` engine on the
mounted hidden inputs and re-derives expected results here with z3. Also
validates /app/answer.json and the absence of forbidden Coq tactic tokens.

Exit 0 on full pass; non-zero on any failure.
"""
import itertools, json, os, re, subprocess, sys
from z3 import *

SOLVE = ["/usr/bin/python3", "/app/solve.py"]
H = "/tests/hidden"
FAILURES = []


def fail(msg):
    FAILURES.append(msg)
    sys.stderr.write("FAIL: %s\n" % msg)


def run(cmd, inp=None):
    r = subprocess.run(cmd, capture_output=True, text=True, input=inp)
    return r.returncode, r.stdout, r.stderr


# ---------------------------------------------------------------- WCNF reference
def parse_wcnf(path):
    hard, soft = [], []
    for ln in open(path):
        ln = ln.strip()
        if not ln or ln.startswith('c') or ln == '%' or ln.startswith('p '):
            continue
        t = ln.split()
        if t[0] == 'top':
            hard.append([int(x) for x in t[1:-1]])
        else:
            soft.append((int(t[0]), [int(x) for x in t[1:-1]]))
    return hard, soft


def wcnf_optimum(hard, soft):
    var_ids = {}

    def var(a):
        a = abs(a)
        if a not in var_ids:
            var_ids[a] = Bool('v%d' % a)
        return var_ids[a]

    def lit(b):
        return var(b) if b > 0 else Not(var(-b))

    opt = Optimize()
    for cl in hard:
        opt.add(Or([lit(l) for l in cl]))
    inds = []
    for (w, cl) in soft:
        b = Bool('i%d' % len(inds))
        inds.append((b, w))
        opt.add(Implies(b, Or([lit(l) for l in cl])))
        opt.maximize(If(b, w, 0))
    if opt.check() != sat:
        return None
    m = opt.model()
    return sum(w for (b, w) in inds if m.eval(b, model_completion=True))


def check_wcnf():
    for fn in ("h1.wcnf", "h2.wcnf"):
        path = "%s/wcnf/%s" % (H, fn)
        rc, out, err = run(SOLVE + ["wcnf", path])
        ref = wcnf_optimum(*parse_wcnf(path))
        mm = re.search(r'^OPT\s+(-?\d+)\s*$', out, re.M)
        got = mm.group(1) if mm else None
        if ref is None:
            if got != 'UNSAT':
                fail("wcnf %s: expected UNSAT got=%r rc=%d" % (fn, got, rc))
        elif got is None or int(got) != ref:
            fail("wcnf %s: got=%r ref=%d rc=%d err=%r" % (fn, got, ref, rc, err[:120]))


# ---------------------------------------------------------------- QF_BV reference
def check_qfbv():
    for fn, expect in (("qfbv1.smt2", 'sat'), ("qfbv2.smt2", 'unsat')):
        src = open("%s/qfbv/%s" % (H, fn)).read()
        rc, out, err = run(SOLVE + ["qfbv"], inp=src)
        verdict = out.strip().splitlines()[0] if out.strip() else None
        # independent re-check of the SMT script
        t = re.sub(r'\((?:check-sat|get-model|exit)\)', '', src)
        t = re.sub(r'\(set-(?:logic|option)\s+[^)]*\)', '', t)
        s = Solver()
        for a in parse_smt2_string(t):
            s.add(a)
        r = s.check()
        if r == sat:
            ref = 'sat'
        elif r == unsat:
            ref = 'unsat'
        else:
            ref = 'unknown'
        if verdict != expect:
            fail("qfbv %s: got=%r need=%r (refsolver=%r) rc=%d" % (fn, verdict, expect, ref, rc))
        if ref != expect:
            fail("qfbv %s: reference solver disagrees with declared expectation" % fn)


# ---------------------------------------------------------------- seats reference
ONES = {0:'zero',1:'one',2:'two',3:'three',4:'four',5:'five',6:'six',7:'seven',
        8:'eight',9:'nine',10:'ten',11:'eleven',12:'twelve',13:'thirteen',14:'fourteen',
        15:'fifteen',16:'sixteen',17:'seventeen',18:'eighteen',19:'nineteen'}
TENS = {2:'twenty',3:'thirty',4:'forty',5:'fifty',6:'sixty',7:'seventy',8:'eighty',9:'ninety'}


def word(n):
    if n < 20:
        return ONES[n]
    o, d = n % 10, n // 10
    if d < 10:
        return TENS[d] + ('' if o == 0 else '-' + ONES[o])
    return str(n)


def letter_count(n):
    return len([c for c in word(n) if c.isalpha()])


def fixed_point(k):
    n, steps = k, 0
    while True:
        c = letter_count(n)
        steps += 1
        if c == n:
            return n, word(n).replace('-', '').replace(' ', ''), steps
        n = c


def ref_seats(path):
    people, focus, friends, enemies = [], None, set(), set()
    for ln in open(path):
        ln = ln.split('#')[0].strip()
        if not ln:
            continue
        k, _, v = ln.partition(':')
        k, v = k.strip(), v.strip()
        if k == 'people':
            people = [x.strip() for x in v.split(',') if x.strip()]
        elif k == 'focus':
            focus = v
        elif k == 'allies':
            for ab in v.split(','):
                if len(ab) == 3 and ab[1] == '-':
                    friends.add(frozenset((ab[0], ab[2])))
        elif k == 'enemies':
            for ab in v.split(','):
                if len(ab) == 3 and ab[1] == '-':
                    enemies.add(frozenset((ab[0], ab[2])))
    n = len(people)

    def legal(seq):
        for i in range(n):
            if frozenset((seq[i], seq[(i + 1) % n])) in enemies:
                return False
        for i in range(n):
            nb = {seq[(i - 1) % n], seq[(i + 1) % n]}
            if not any(frozenset((seq[i], q)) in friends for q in nb):
                return False
        fi = seq.index(focus)
        nb = {seq[(fi - 1) % n], seq[(fi + 1) % n]}
        return len(nb) == 2 and all(frozenset((focus, q)) in friends for q in nb)

    boards = set()
    for perm in itertools.permutations(people):
        if perm[0] == focus and legal(perm):
            boards.add(''.join(perm))
    boards = sorted(boards)
    pairs = set()
    for b in boards:
        i = b.index(focus)
        pairs.add(b[(i - 1) % n])
        pairs.add(b[(i + 1) % n])
    fix, phrase, steps = fixed_point(len(boards))
    return focus, sorted(pairs), boards, fix


def check_seats():
    path = "%s/seats/seats_hidden.txt" % H
    focus, pairs, boards, fix = ref_seats(path)
    rc, out, err = run(SOLVE + ["seats", path])
    lines = out.splitlines()
    if not lines:
        fail("seats hidden: no output rc=%d err=%r" % (rc, err[:150]))
        return
    got_focus = lines[0][6:].strip() if lines[0].startswith('FOCUS ') else None
    if got_focus != focus:
        fail("seats focus got=%s ref=%s" % (got_focus, focus))
    got_pairs = None
    nb = None
    fix_v = None
    phrase = None
    steps = None
    got_boards = []
    for l in lines:
        if l.startswith('PAIRS '):
            got_pairs = [x.strip() for x in l[6:].strip().split(',')]
        elif l.startswith('NBOARDS '):
            try:
                nb = int(l[8:].strip())
            except ValueError:
                nb = None
        elif re.match(r'^[A-Z]+$', l.strip()):
            got_boards.append(l.strip())
        elif l.startswith('FIXPOINT '):
            try:
                fix_v = int(l[9:].strip())
            except ValueError:
                fix_v = None
        elif l.startswith('PHRASE '):
            phrase = l[7:].strip()
        elif l.startswith('STEPS '):
            steps = l[6:].strip()
    if got_pairs != pairs:
        fail("seats pairs got=%s ref=%s" % (got_pairs, pairs))
    if nb != len(boards):
        fail("seats nboards got=%s ref=%d" % (nb, len(boards)))
    if got_boards != boards:
        fail("seats boards differ: got %d ref %d" % (len(got_boards), len(boards)))
    if fix_v != fix:
        fail("seats fixpoint got=%s ref=%d" % (fix_v, fix))


# ---------------------------------------------------------------- answer.json
def check_answer():
    A = json.load(open('/app/answer.json'))
    ref = wcnf_optimum(*parse_wcnf('/app/instance.wcnf'))
    if A.get('wcnf_opt') != ref:
        fail("answer.json wcnf_opt=%s ref=%s" % (A.get('wcnf_opt'), ref))
    if A.get('qfbv') not in ('sat', 'unsat', 'unknown'):
        fail("answer.json qfbv=%r" % A.get('qfbv'))
    s = A.get('seats')
    if not isinstance(s, dict) or s.get('focus') != 'J':
        fail("answer.json seats.focus=%r" % (A.get('seats')))
    sy = A.get('symxe')
    if not isinstance(sy, dict) or sy.get('engine') != 'symxe':
        fail("answer.json symxe=%r" % sy)
    if not isinstance(sy.get('paths'), int) or sy.get('paths') < 2:
        fail("answer.json symxe.paths=%r" % sy.get('paths'))
    if A.get('cert') != 'ok':
        fail("answer.json cert=%r" % A.get('cert'))
    rc, out, err = run(['symxe', '--version'])
    if rc != 0:
        fail("symxe --version rc=%d err=%r" % (rc, err[:150]))


# ---------------------------------------------------------------- Forbidden tokens
FORBIDDEN = re.compile(r'\b(?:auto|eauto|tauto|intuition|firstorder|trivial|easy|now|'
                       r'omega|nia|psatz|ring|field|congruence|crush)\b')


def check_coq():
    for p in ('/app/cert/astral.v', '/app/cert/astral.vo'):
        if not os.path.exists(p):
            fail("missing %s" % p)
            return
    for i, ln in enumerate(open('/app/cert/astral.v'), 1):
        for m in FORBIDDEN.finditer(ln):
            fail("forbidden token %r in astral.v:%d" % (m.group(0), i))
    # ensure second file is not empty
    if os.path.getsize('/app/cert/astral.vo') == 0:
        fail("astral.vo is empty")


def main():
    check_wcnf()
    check_qfbv()
    check_seats()
    check_answer()
    check_coq()
    if FAILURES:
        sys.stderr.write("%d failure(s)\n" % len(FAILURES))
        sys.exit(1)
    sys.stdout.write("VERIFY_PASS\n")


if __name__ == '__main__':
    main()