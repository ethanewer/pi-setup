#!/usr/bin/env python3
"""kite-anchor verifier core. Independent of the oracle implementation.

Recomputes every expected value from the documented contracts and compares
against the agent's deliverables at /app and hidden fixtures at /tests/hidden.
Emits a per-check PASS/FAIL log and writes the final reward to
/logs/verifier/reward.txt (1 or 0).
"""
import math
import os
import re
import subprocess
import sys

HIDDEN = '/tests/hidden'
APP = '/app'
MASK32 = 0xFFFFFFFF

failed = []


def ok(name, cond, detail=''):
    if cond:
        print('PASS  %s' % name)
    else:
        print('FAIL  %s  %s' % (name, detail))
        failed.append(name)


# ---------------- shared reference algorithms ----------------

def lcg(s):
    return (s * 1664525 + 1013904223) & MASK32


def sample(seed, length):
    s = seed & MASK32
    out = []
    prev = -1
    for _ in range(length):
        s = lcg(s)
        best = -1
        bestsc = -1
        for tok in range(26):
            s2 = lcg((s ^ (tok * 2654435761)) & MASK32)
            sc = (prev << 3) + tok + 1024
            sc2 = (sc * 31 + (s2 & 0xFF)) % 1000003
            if sc2 > bestsc:
                bestsc = sc2
                best = tok
        out.append(chr(97 + best))
        prev = best
    return ''.join(out)


def mips_checksum(cells, total, steps):
    acc = 0
    seed = 0x12345678
    for i in range(1, steps + 1):
        seed = (seed * 1103515245 + 12345) & MASK32
        h = cells[(i - 1) % total]
        acc = (acc * 33 + h + ((seed >> 16) & 0x7f)) & MASK32
    return acc


def fort_range(v0, ang):
    return v0 * v0 * math.sin(2 * math.radians(ang)) / 9.80665


def recon(n):
    base = 31337
    rows = []
    tx = ty = tz = 0
    mass = 0
    mn = [10 ** 40] * 3
    mx = [-1] * 3
    for i in range(n):
        s = (base + i * 2654435761) & MASK32
        s = lcg(s); r0 = s
        s = lcg(s); r1 = s
        s = lcg(s); r2 = s
        s = lcg(s); m = 3 + ((s >> 20) & 3)
        x = r0 % 1000000; y = r1 % 1000000; z = r2 % 1000000
        rows.append((i, x, y, z, m))
        tx += x; ty += y; tz += z; mass += m
        for k, v in ((0, x), (1, y), (2, z)):
            mn[k] = min(mn[k], v); mx[k] = max(mx[k], v)
    return rows, (tx, ty, tz, mass, mx[0] - mn[0], mx[1] - mn[1], mx[2] - mn[2])


def read_boards(path):
    with open(path) as f:
        lines = f.read().split()
    W, H = int(lines[0]), int(lines[1])
    cells = [int(x) for x in lines[2:2 + W * H]]
    return cells, W, H


# ---------------- checks ----------------

def check_game():
    p = '/app/game.mips'
    ok('game.mips present', os.path.isfile(p))
    if not os.path.isfile(p):
        return
    out = subprocess.run(['file', p], capture_output=True, text=True).stdout
    ok('game.mips is MIPS ELF', 'MIPS' in out or 'mips' in out.lower(), out.strip())
    cases = []
    with open(os.path.join(HIDDEN, 'mips_trials.txt')) as f:
        for line in f:
            line = line.split()
            if len(line) == 2:
                cases.append((line[0], int(line[1])))
    for board, steps in cases:
        cells, W, H = read_boards(os.path.join(HIDDEN, board))
        total = W * H
        expected = mips_checksum(cells, total, steps)
        r = subprocess.run(['qemu-mipsel-static', p, os.path.join(HIDDEN, board), str(steps)],
                           capture_output=True, text=True)
        got = r.stdout.strip()
        ok('game.mips %s steps=%d' % (board, steps),
           r.returncode == 0 and got == str(expected),
           'got=%s expected=%s rc=%d' % (got, expected, r.returncode))


def check_fortran():
    p = '/app/main'
    ok('main present', os.path.isfile(p))
    # Makefile must rebuild /app/main with gfortran.  Plain `make` on an
    # up-to-date tree echoes nothing ("Nothing to be done"), so the gfortran
    # frontend would never surface in the log: the previous check was vacuous
    # and failed correct agents whose build tree was already current.  Instead
    # (a) require the Makefile text itself to drive the gfortran frontend, and
    # (b) force a full rebuild with make -B so gfortran must actually be
    # invoked in the compile log.
    mk = '/app/Makefile'
    ok('Makefile present', os.path.isfile(mk))
    if os.path.isfile(mk):
        try:
            mktext = open(mk).read()
        except Exception as e:
            mktext = ''
            ok('Makefile readable', False, repr(e))
        ok('Makefile drives gfortran frontend', 'gfortran' in mktext,
           'no gfortran frontend reference in /app/Makefile')
        r = subprocess.run(['make', '-B', '-f', mk, '-C', APP],
                           capture_output=True, text=True)
        logtail = (r.stdout + r.stderr).strip().splitlines()[-6:]
        ok('make -B rebuild succeeds', r.returncode == 0, ' | '.join(logtail))
        ok('gfortran invoked during rebuild',
           r.returncode == 0 and 'gfortran' in r.stdout + r.stderr,
           ' | '.join(logtail))
    if not os.path.isfile(p):
        return
    angles = []
    with open(os.path.join(HIDDEN, 'fort_angles.txt')) as f:
        for line in f:
            vals = line.split()
            if len(vals) == 2:
                angles.append((float(vals[0]), float(vals[1])))
    for v0, ang in angles:
        r = subprocess.run(['sh', '-c', 'echo "%s %s" | %s' % (v0, ang, p)],
                           capture_output=True, text=True)
        got = float(r.stdout.strip())
        exp = fort_range(v0, ang)
        tol = max(0.5, abs(exp) * 0.02)
        ok('main %.0f %.0f deg -> %.3f' % (v0, ang, exp),
           abs(got - exp) <= tol, 'got=%s exp=%.3f' % (got, exp))


def check_polyglot():
    src = '/app/poly.c'
    ok('poly.c present', os.path.isfile(src))
    if not os.path.isfile(src):
        return
    r = subprocess.run(['gcc', '-o', '/tmp/pc', src], capture_output=True, text=True)
    out = subprocess.run(['/tmp/pc'], capture_output=True, text=True).stdout.strip()
    ok('poly.c compiles+runs as C', r.returncode == 0 and out == 'poly:c=0', 'out=%s' % out)
    r2 = subprocess.run(['g++', '-o', '/tmp/pcpp', src], capture_output=True, text=True)
    out2 = subprocess.run(['/tmp/pcpp'], capture_output=True, text=True).stdout.strip()
    ok('poly.c compiles+runs as C++ (differs)', r2.returncode == 0 and out2 == 'poly:c=1', 'out=%s' % out2)


def check_cli():
    app = '/app/app'
    ok('app present', os.path.isfile(app))
    if not os.path.isfile(app):
        return
    cases = []
    with open(os.path.join(HIDDEN, 'cli.txt')) as f:
        for line in f:
            vals = line.split()
            if len(vals) == 2:
                cases.append((int(vals[0]), int(vals[1])))
    for n, t in cases:
        pos = '/tmp/cli_%d_pos.txt' % n
        summ = '/tmp/cli_%d_sum.txt' % n
        r = subprocess.run([app, '-n', str(n), '-p', pos, '-s', summ, '-t', str(t)],
                           capture_output=True, text=True)
        rows, stat = recon(n)
        ok('app CLI n=%d t=%d runs' % (n, t), r.returncode == 0, r.stderr[-300:])
        # stdout line
        want_stdout = 'particles=%d sum_x=%d sum_y=%d threads=%d' % (n, stat[0], stat[1], t)
        ok('app CLI stdout n=%d' % n, r.stdout.strip() == want_stdout,
           'got=%s want=%s' % (r.stdout.strip(), want_stdout))
        # position file
        try:
            got_rows = []
            with open(pos) as f:
                lines = f.read().strip().split('\n')
            ok('app CLI pos header n=%d' % n, lines[0] == '# i,x,y,z,m', lines[0])
            for ln in lines[1:]:
                got_rows.append(tuple(int(x) for x in ln.split(',')))
            want_rows = [(i, x, y, z, m) for (i, x, y, z, m) in rows]
            ok('app CLI pos rows n=%d' % n, got_rows == want_rows,
               'got[0]=%s want[0]=%s len got=%d want=%d' % (
                   got_rows[0] if got_rows else None,
                   want_rows[0] if want_rows else None, len(got_rows), len(want_rows)))
        except Exception as e:
            ok('app CLI pos parse n=%d' % n, False, repr(e))
        # summary file
        try:
            with open(summ) as f:
                s = f.read()
            want_sum = [
                'count=%d' % n,
                'mass_sum=%d' % stat[3],
                'total_x=%d' % stat[0],
                'total_y=%d' % stat[1],
                'total_z=%d' % stat[2],
                'extent_x=%d' % stat[4],
                'extent_y=%d' % stat[5],
                'extent_z=%d' % stat[6],
            ]
            ok('app CLI summary n=%d' % n, s.strip() == '\n'.join(want_sum),
               'got[:1]=%r' % s.strip().split('\n')[:2])
        except Exception as e:
            ok('app CLI summary parse n=%d' % n, False, repr(e))


def check_launcher():
    app = '/app/app'
    if not os.path.isfile(app):
        return
    cases = []
    with open(os.path.join(HIDDEN, 'launch.txt')) as f:
        for line in f:
            vals = line.split()
            if len(vals) == 2:
                cases.append((int(vals[0]), int(vals[1])))
    for length, seed in cases:
        r = subprocess.run(['python3', os.path.join(APP, 'launcher.py'), 'sample', str(length), str(seed)],
                           cwd=APP, capture_output=True, text=True)
        ok('launcher sample len=%d seed=%d' % (length, seed),
           r.returncode == 0 and r.stdout.strip() == 'LAUNCH_OK %d %d' % (length, seed),
           'out=%s rc=%d' % (r.stdout.strip(), r.returncode))


def check_key():
    app = '/app/app'
    src = os.path.join(APP, 'sources', 'kite_app.c')
    keyfile = '/app/key.txt'
    ok('key.txt present', os.path.isfile(keyfile))
    ok('kite_app.c source present', os.path.isfile(src))
    if not (os.path.isfile(app) and os.path.isfile(src)):
        return
    # rebuild the sampler from source with the system compiler
    r = subprocess.run(['gcc', '-O2', '-o', '/tmp/ref_app', src], capture_output=True, text=True)
    ok('from-source rebuild compiles', r.returncode == 0, r.stderr[-300:])

    def key_of(binary, seed):
        r = subprocess.run([binary, 'key', str(seed)], capture_output=True, text=True)
        return r.stdout.strip()

    # 1) official release seeds in key.txt must equal the recompiled binary
    seeds = []
    with open(os.path.join(APP, 'sources', 'key_seeds.txt')) as f:
        seeds = [int(x) for x in f.read().split() if x.strip()]
    entries = {}
    with open(keyfile) as f:
        for line in f:
            line = line.strip()
            if '=' in line:
                k, v = line.split('=', 1)
                entries[k] = v
    all_ok = True
    for s in seeds:
        want = key_of('/tmp/ref_app', s)
        got = entries.get(str(s))
        if got != want:
            all_ok = False
            print('  ...seed %d got=%r want=%r' % (s, got, want))
    ok('key.txt consistent with recompiled binary (all official seeds)', all_ok)
    ok('key.txt covers every official seed', set(entries.keys()) == set(str(s) for s in seeds),
       'extra/missing=%s' % sorted(set(entries) ^ set(str(s) for s in seeds)))
    # 2) shipped binary is honest: agree with the recompiled binary on hidden seeds
    extra = []
    with open(os.path.join(HIDDEN, 'extra_seeds.txt')) as f:
        extra = [int(x) for x in f.read().split() if x.strip()]
    hon = all(key_of(app, s) == key_of('/tmp/ref_app', s) for s in extra)
    ok('shipped app binary honest on hidden seeds (recompile independence)', hon)


def check_scheme():
    sp = '/app/scheme.py'
    ok('scheme.py present', os.path.isfile(sp))
    if not os.path.isfile(sp):
        return
    for prog, exp in [('scheme1.prog', 'scheme1.out'), ('scheme2.prog', 'scheme2.out')]:
        r = subprocess.run(['python3', sp], stdin=open(os.path.join(HIDDEN, prog)),
                           capture_output=True, text=True)
        want = open(os.path.join(HIDDEN, exp)).read()
        ok('scheme.py %s' % prog, r.returncode == 0 and r.stdout == want,
           'got=%r want=%r' % (r.stdout, want))


def _write_reward(reward):
    try:
        os.makedirs('/logs/verifier', exist_ok=True)
        with open('/logs/verifier/reward.txt', 'w') as f:
            f.write(str(reward))
    except Exception as e:
        print('WARN  could not write reward.txt: %r' % (e,))


def main():
    # Crash-proof verifier: even if a check raises unexpectedly, reward.txt must
    # still be written (0) so the harness never sees an absent reward.
    try:
        check_game()
        check_fortran()
        check_polyglot()
        check_cli()
        check_launcher()
        check_key()
        check_scheme()
    except Exception as e:
        print('VERIFIER CRASH: %r' % (e,))
        failed.append('verifier-crash')
    reward = 0 if failed else 1
    print('----')
    print('TOTAL_FAILED=%d' % len(failed))
    print('REWARD=%d' % reward)
    _write_reward(reward)
    return 0


if __name__ == '__main__':
    sys.exit(main())