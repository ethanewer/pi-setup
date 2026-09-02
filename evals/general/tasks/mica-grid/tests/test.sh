#!/bin/bash
# Verifier for mica-grid (executes-deliverable).
# Executes /app/sudoku.py on the shipped board and on every hidden board under
# /tests/hidden, enforcing the 0/1/2 exit-code contract and exact-match
# solutions (rows/columns/boxes valid, givens preserved). Writes 1/0 to
# /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0

PRISTINE_PUZZLE_SHA="d1d898a37111a741f8f48992759871616022792651602225c79186d2af575e8a"

no_modify_broken=0
if [ ! -f /app/puzzle.txt ]; then
    echo "no-modify: /app/puzzle.txt missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/puzzle.txt | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_PUZZLE_SHA" ]; then
        echo "no-modify: /app/puzzle.txt was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/sudoku.py"
SOLVED_TXT = "/app/solved.txt"
no_modify_broken = int(sys.argv[1])


def load_expected(d):
    try:
        with open(os.path.join(d, 'expected.json')) as fh:
            return json.load(fh), None
    except Exception as exc:
        return None, 'expected.json unreadable: %r' % (exc,)


def valid_solution(lines, given_lines):
    """lines: 9 strings of 9 digits. Returns error or None."""
    if len(lines) != 9 or any(len(l) != 9 for l in lines):
        return 'output is not 9 lines of 9 characters'
    if any(ch not in '123456789' for l in lines for ch in l):
        return 'output contains characters other than digits 1-9'
    g = [[ch for ch in l] for l in lines]
    for i in range(9):
        if sorted(g[i]) != list('123456789'):
            return 'row %d invalid' % i
        col = [g[r][i] for r in range(9)]
        if sorted(col) != list('123456789'):
            return 'column %d invalid' % i
    for br in range(0, 9, 3):
        for bc in range(0, 9, 3):
            box = [g[r][c] for r in range(br, br + 3) for c in range(bc, bc + 3)]
            if sorted(box) != list('123456789'):
                return 'box (%d,%d) invalid' % (br, bc)
    # givens preserved
    for r in range(9):
        for c in range(9):
            gv = given_lines[r][c]
            if isinstance(gv, str) and gv in '123456789' and g[r][c] != gv:
                return 'given at (%d,%d) changed' % (r, c)
    return None


def run_solver(board_path, out_path):
    if os.path.exists(out_path):
        os.remove(out_path)
    try:
        r = subprocess.run([sys.executable, SOLVE, board_path, out_path],
                           capture_output=True, text=True, timeout=120)
    except Exception as exc:
        return None, 'solver raised %r' % (exc,)
    return r, None


def check_case(board_path, expected):
    """Returns list of failure strings for one board case."""
    bad = []
    out = '/tmp/mica_out_%d.txt' % os.getpid()
    r, err = run_solver(board_path, out)
    if err:
        return [err]
    want_rc = expected['rc']
    if r.returncode != want_rc:
        bad.append('exit %d != expected %d (stderr: %s)'
                   % (r.returncode, want_rc, r.stderr[:120]))
        return bad
    if want_rc != 0:
        return bad
    # solvable: parse output
    try:
        with open(out) as fh:
            text = fh.read()
    except Exception as exc:
        return ['output file unreadable: %r' % (exc,)]
    lines = text.split('\n')
    while lines and lines[-1] == '':
        lines.pop()
    # given board for preservation check
    try:
        with open(board_path) as fh:
            raw = [ln.rstrip('\r\n') for ln in fh.read().split('\n')]
        while raw and raw[-1].strip() == '':
            raw.pop()
        given = [[0 if ch in '0.' else ch for ch in ln.strip()] for ln in raw]
    except Exception:
        given = [[0] * 9 for _ in range(9)]
    msg = valid_solution(lines, given)
    if msg:
        bad.append(msg)
        return bad
    if '\n'.join(lines) + '\n' != expected['solution']:
        bad.append('output does not match the reference solution')
    return bad


failures = []
if no_modify_broken:
    failures.append('shipped puzzle modified or missing (no-modify rule)')

if not os.path.isfile(SOLVE):
    failures.append('missing /app/sudoku.py')
else:
    # --- shipped board ---
    if os.path.isfile('/app/puzzle.txt'):
        try:
            with open('/tests/expected_shipped.json') as fh:
                exp = json.load(fh)
        except Exception as exc:
            exp = None
            failures.append('shipped expected missing: %r' % (exc,))
        if exp:
            failures.extend('shipped: ' + b for b in
                            check_case('/app/puzzle.txt', exp))
        # /app/solved.txt must equal the reference solution
        if not os.path.isfile(SOLVED_TXT):
            failures.append('missing /app/solved.txt')
        elif exp:
            try:
                with open(SOLVED_TXT) as fh:
                    got = fh.read()
                if got != exp['solution']:
                    failures.append('/app/solved.txt != reference solution')
            except Exception as exc:
                failures.append('/app/solved.txt unreadable: %r' % (exc,))

    # --- hidden cases ---
    hidden_dir = '/tests/hidden'
    if not os.path.isdir(hidden_dir):
        failures.append('no hidden cases present')
    else:
        cases = sorted(d for d in os.listdir(hidden_dir)
                       if os.path.isdir(os.path.join(hidden_dir, d)))
        if not cases:
            failures.append('no hidden cases present')
        for c in cases:
            base = os.path.join(hidden_dir, c)
            board = os.path.join(base, 'board.txt')
            exp, err = load_expected(base)
            if err or not os.path.isfile(board):
                failures.append("hidden '%s': %s" % (c, err or 'missing board.txt'))
                continue
            try:
                failures.extend("hidden %s: %s" % (c, b)
                                for b in check_case(board, exp))
            except Exception as exc:
                failures.append("hidden '%s': checker exception %r" % (c, exc))

print('verify failures:', failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0