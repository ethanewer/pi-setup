#!/usr/bin/env bash
# Verifier for onyx-upland.  Runs every /app deliverable (the five reporting
# programs) on the shipped fixtures AND on the hidden inputs, recomputes the
# expected outputs independently, and requires byte-level equality.  Writes
# reward to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier

python3 - <<'PY'
import csv, glob, os, subprocess, sys, tomllib

BAD = []

def fail(msg):
    BAD.append(msg)

def run_py(prog, *args):
    try:
        r = subprocess.run(['python3', prog] + list(args),
                           capture_output=True, text=True, timeout=60)
    except subprocess.TimeoutExpired:
        fail('TIMEOUT running %s %s' % (prog, args))
        return False
    if r.returncode != 0:
        fail('program %s %s exited %d: %s' % (prog, args, r.returncode, r.stderr[:400]))
        return False
    return True

def read_rows(path):
    with open(path, newline='') as f:
        out = []
        for row in csv.reader(f):
            if not row or all(c.strip() == '' for c in row):
                continue
            out.append(row)
    return out

# ---------------- independent expected computations ----------------

def exp_aggregate(inp):
    rows = read_rows(inp)
    data = rows[1:] if rows else []
    cats = {}
    for r in data:
        if len(r) < 3:
            continue
        c = r[0].strip(); a = int(r[1]); q = int(r[2])
        cats.setdefault(c, [0, 0])
        cats[c][0] += a; cats[c][1] += q
    lines = ['category,total_amount,total_qty']
    for c in sorted(cats):
        lines.append('%s,%d,%d' % (c, cats[c][0], cats[c][1]))
    lines.append('TOTAL,%d,%d' % (sum(v[0] for v in cats.values()),
                                  sum(v[1] for v in cats.values())))
    return ('\n'.join(lines) + '\n').encode()

def exp_ordered(inp):
    rows = read_rows(inp)
    data = rows[1:] if rows else []
    acc = []
    for r in data:
        if len(r) < 4:
            continue
        pid = r[0].strip(); st = r[1].strip()
        rev = int(r[2]); prio = int(r[3])
        if st == 'accepted':
            acc.append((pid, rev, prio))
    acc.sort(key=lambda x: (-x[1], x[2], x[0]))
    lines = ['product_id,revenue,priority']
    for pid, rev, prio in acc:
        lines.append('%s,%d,%d' % (pid, rev, prio))
    return ('\n'.join(lines) + '\n').encode()

def exp_tally(inp):
    rows = read_rows(inp)
    data = rows[1:] if rows else []
    total = 0; nf = 0; ids = []
    for r in data:
        if len(r) < 3:
            continue
        total += 1
        if r[2].strip() == 'not_found':
            nf += 1; ids.append(r[0].strip())
    lines = ['=== SCAN TALLY ===', 'total=%d' % total,
             'resolved=%d' % (total - nf), 'not_found=%d' % nf,
             '=== NOT-FOUND ENTRIES ==='] + ids
    return ('\n'.join(lines) + '\n').encode()

def exp_frames(inp):
    start = None; stop = None
    with open(inp) as f:
        for line in f:
            line = line.rstrip('\n').rstrip('\r')
            if not line.strip() or line.strip().startswith('#'):
                continue
            if '=' in line:
                k, v = line.split('=', 1)
                k = k.strip(); v = v.strip()
                if k == 'start': start = int(v)
                elif k == 'stop': stop = int(v)
    low, high = min(start, stop), max(start, stop)
    return ('low = %d\nhigh = %d\n' % (low, high)).encode()

def exp_fixed(inp):
    rows = read_rows(inp)
    data = rows[1:] if rows else []
    buf = []
    for r in data:
        if len(r) < 4:
            continue
        seq = int(r[0].strip()); name = r[1].strip()
        code = r[2].strip(); value = int(r[3].strip())
        line = '%4d%-8s%-5s%8d' % (seq, name[:8], code[:5], value)
        buf.append((line + '\n').encode())
    return b''.join(buf)

def check_bytes(what, got, exp):
    if got != exp:
        fail('%s byte mismatch:\n  got: %r\n  exp: %r' % (what, got[:200], exp[:200]))

# ---------------- deliverables present ----------------

PROGS = ['/app/aggregate.py', '/app/ordered.py', '/app/tally.py',
         '/app/frames.py', '/app/fixed_width.py']
ARTS = ['/app/summary.csv', '/app/results.csv', '/app/report.txt',
        '/app/frames.toml', '/app/records.bin']
for p in PROGS:
    if not os.path.isfile(p) or os.path.getsize(p) == 0:
        fail('missing deliverable %s' % p)
for a in ARTS:
    if not os.path.isfile(a):
        fail('missing artifact %s' % a)

TF = '/tmp/vt'

# ---------------- public fixtures: fresh run + committed artifact ----------------

def public(prog, art, fixture, expected_fn, kind):
    got = TF + '.out'
    if not run_py(prog, fixture, got):
        return
    with open(got, 'rb') as f:
        fresh = f.read()
    check_bytes('%s fresh run on %s' % (prog, fixture), fresh, expected_fn(fixture))
    with open(art, 'rb') as f:
        committed = f.read()
    check_bytes('artifact %s' % art, committed, expected_fn(fixture))
    if kind == 'toml':
        try:
            d = tomllib.loads(committed.decode())
        except Exception as e:
            fail('frames.toml not loadable by toml parser: %s' % e)
            return
        if sorted(d.keys()) != ['high', 'low'] or not isinstance(d['low'], int) \
           or not isinstance(d['high'], int) or d['low'] > d['high']:
            fail('frames.toml schema wrong: %r' % d)
    os.remove(got) if os.path.exists(got) else None

public('/app/aggregate.py', '/app/summary.csv', '/app/sales.csv', exp_aggregate, 'csv')
public('/app/ordered.py', '/app/results.csv', '/app/orders.csv', exp_ordered, 'csv')
public('/app/tally.py', '/app/report.txt', '/app/statuses.csv', exp_tally, 'txt')
public('/app/frames.py', '/app/frames.toml', '/app/frames.conf', exp_frames, 'toml')
public('/app/fixed_width.py', '/app/records.bin', '/app/inventory.csv', exp_fixed, 'bin')

# ---------------- hidden scenarios ----------------

def hidden(prog, directory, expected_fn, kind):
    files = sorted(glob.glob(directory + '/*.csv') + glob.glob(directory + '/*.conf'))
    for finp in files:
        got = TF + '.h'
        if not run_py(prog, finp, got):
            continue
        with open(got, 'rb') as f:
            fresh = f.read()
        check_bytes('%s hidden input %s' % (prog, os.path.basename(finp)),
                    fresh, expected_fn(finp))
        if kind == 'toml':
            try:
                d = tomllib.loads(fresh.decode())
            except Exception as e:
                fail('hidden frames output not toml: %s' % e)
                continue
            if sorted(d.keys()) != ['high', 'low'] or not isinstance(d['low'], int) \
               or not isinstance(d['high'], int) or d['low'] > d['high']:
                fail('hidden frames schema bad for %s: %r' % (finp, d))
        os.remove(got) if os.path.exists(got) else None

hidden('/app/aggregate.py', '/tests/hidden/aggregate', exp_aggregate, 'csv')
hidden('/app/ordered.py', '/tests/hidden/ordered', exp_ordered, 'csv')
hidden('/app/tally.py', '/tests/hidden/tally', exp_tally, 'txt')
hidden('/app/frames.py', '/tests/hidden/frames', exp_frames, 'toml')
hidden('/app/fixed_width.py', '/tests/hidden/fixed', exp_fixed, 'bin')

# ---------------- verdict ----------------

if BAD:
    print('VERIFIER: %d FAILURE(S)' % len(BAD))
    for b in BAD:
        print(' - ' + b)
    sys.exit(1)
print('VERIFIER: all checks passed')
PY

rc=$?
if [ "$rc" -eq 0 ]; then
  echo 1 > /logs/verifier/reward.txt
  echo "REWARD=1"
else
  echo 0 > /logs/verifier/reward.txt
  echo "REWARD=0"
fi
exit 0