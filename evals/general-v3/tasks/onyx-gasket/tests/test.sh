#!/bin/bash
# Verifier for onyx-gasket (executes-deliverable).
#
# Executes /app/repair.sh idempotently, then independently replays every
# originally-failing check plus the hidden edge cases. Reward is 1 only when
# every gate passes.
set -u
mkdir -p /logs/verifier
reward=0

if python3 - <<'PY'
import asyncio
import json
import os
import subprocess
import sys

HD = '/tests/hidden'
probs = []


def check(name, cond, detail=''):
    if not cond:
        probs.append('%s  <%s>' % (name, str(detail)[-200:]))


def fnv1a(data):
    h = 0x811C9DC5
    for b in data:
        h ^= b
        h = (h * 0x01000193) & 0xFFFFFFFF
    return h


def xorshift_bytes(seed, length):
    out = bytearray()
    x = seed & 0xFFFFFFFF
    for _ in range(length):
        x ^= (x << 13) & 0xFFFFFFFF
        x ^= x >> 17
        x ^= (x << 5) & 0xFFFFFFFF
        out.append(x & 0xFF)
    return bytes(out)


def build_content(case):
    if 'hex' in case:
        return bytes.fromhex(case['hex'])
    kind = case.get('kind', 'byte')
    length = int(case['length'])
    if kind == 'byte':
        return bytes([int(case['fill'], 0) & 0xFF]) * length
    if kind == 'pattern':
        return xorshift_bytes(int(case['seed']), length)
    raise ValueError('unknown kind')


# ---- execute deliverable /app/repair.sh (must be idempotent, exit 0) ----
r = subprocess.run(['bash', '/app/repair.sh'], capture_output=True, text=True)
check('repair_sh_exit0', r.returncode == 0, r.stdout[-200:] + r.stderr[-200:])

# ---- deliverable /app/env.txt -> conda env present & working ----
envname = ''
try:
    envname = open('/app/env.txt').read().strip()
except Exception as exc:
    check('env_file_readable', False, exc)
check('env_name_nonempty', bool(envname), repr(envname))
if envname:
    el = subprocess.run(['/opt/miniconda3/bin/conda', 'env', 'list'],
                        capture_output=True, text=True)
    check('conda_env_listed', envname in (el.stdout + el.stderr), el.stdout)
    cr = subprocess.run(
        ['/opt/miniconda3/bin/conda', 'run', '-n', envname, 'python', '-c',
         'import itsdangerous'],
        capture_output=True, text=True)
    check('conda_env_working', cr.returncode == 0, cr.stdout + cr.stderr)

# ---- deliverable /app/rebuilt: real ELF native module ----
try:
    so = [p for p in os.listdir('/app/rebuilt')
          if p.startswith('_native') and p.endswith('.so')]
    check('rebuilt_has_so', len(so) > 0, os.listdir('/app/rebuilt'))
    if so:
        with open(os.path.join('/app/rebuilt', so[0]), 'rb') as f:
            magic = f.read(4)
        check('rebuilt_is_elf', magic == b'\x7fELF', so)
except Exception as exc:
    check('rebuilt_glob', False, exc)

# ---- pip restored + small package end-to-end ----
pv = subprocess.run(['python3', '-m', 'pip', '--version'],
                    capture_output=True, text=True)
check('pip_restored', pv.returncode == 0 and 'from' in pv.stdout, pv.stdout + pv.stderr)
try:
    import colorama
    check('small_pkg_import', True)
except Exception as exc:
    check('small_pkg_import', False, exc)

# ---- numpy importable, 2.x ----
try:
    import numpy
    check('numpy_importable', True)
    check('numpy_2x', numpy.__version__.startswith('2.'), numpy.__version__)
except Exception as exc:
    check('numpy_importable', False, exc)

# ---- default-interpreter compiled hailshot ----
try:
    import hailshot
    check('hailshot_native_present', hailshot._native is not None)
    check('hailshot_native_binary', hailshot._native is not None
          and hailshot._native.__file__.endswith('.so'),
          getattr(hailshot._native, '__file__', None))
except Exception as exc:
    check('hailshot_import', False, exc)

# ---- run the repo's targeted async fs unit tests ----
pt = subprocess.run(['python3', '-m', 'pytest', '-q', '/app/hailshot-src/tests'],
                    capture_output=True, text=True)
out = pt.stdout + pt.stderr
check('pytest_green', pt.returncode == 0 and 'passed' in out
      and 'failed' not in out, out[-300:])

# ---- hidden: fingerprint edge cases (native == fallback == independent) ----
bc = json.load(open(os.path.join(HD, 'bytes_cases.json')))
for case in bc:
    data = build_content(case)
    with open('/tmp/hs_hidden.bin', 'wb') as f:
        f.write(data)
    try:
        import hailshot
        n = hailshot.fingerprint('/tmp/hs_hidden.bin', prefer_native=True)
        fb = hailshot.fingerprint('/tmp/hs_hidden.bin', prefer_native=False)
    except Exception as exc:
        check('fp_case_%s' % case['name'], False, exc)
        continue
    check('fp_%s_independent' % case['name'], n == fnv1a(data), (n, fnv1a(data)))
    check('fp_%s_native_eq_fallback' % case['name'], n == fb, (n, fb))

# ---- hidden: async profile/sweep on a nested directory tree ----
ts = json.load(open(os.path.join(HD, 'tree_spec.json')))
import tempfile
import hailshot
with tempfile.TemporaryDirectory() as td:
    try:
        for spec in ts['files']:
            rel = spec['rel']
            path = os.path.join(td, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, 'wb') as f:
                f.write(build_content(spec))
        prof = asyncio.run(hailshot.profile(td))
    except Exception as exc:
        check('tree_profile_run', False, exc)
        prof = {}
    expected = {}
    for spec in ts['files']:
        data = build_content(spec)
        expected[spec['rel']] = fnv1a(data)
    check('tree_profile_key_count', set(prof.keys()) == set(expected.keys()),
          (sorted(prof), sorted(expected)))
    for k, v in expected.items():
        check('tree_profile_fp_%s' % k, prof.get(k) == v, (prof.get(k), v))
        try:
            native = hailshot.fingerprint(os.path.join(td, k), prefer_native=True)
            fb = hailshot.fingerprint(os.path.join(td, k), prefer_native=False)
            check('tree_native_eq_fallback_%s' % k, native == fb, (native, fb))
        except Exception as exc:
            check('tree_fallback_%s' % k, False, exc)
    try:
        cnt, digest = asyncio.run(hailshot.sweep(td))
        check('tree_sweep_count', cnt == len(expected), (cnt, len(expected)))
        expect_digest = 0
        for k, v in expected.items():
            expect_digest = (expect_digest + v) & 0xFFFFFFFFFFFFFFFF
            expect_digest = (expect_digest + len(k)) & 0xFFFFFFFFFFFFFFFF
        check('tree_sweep_digest', digest == expect_digest, (digest, expect_digest))
    except Exception as exc:
        check('tree_sweep_run', False, exc)

# ---- OSMesa loader: normal + bogus-env fallback ----
g = subprocess.run(['python3', '/app/gloss/peregrine.py'],
                   capture_output=True, text=True)
check('osmesa_normal', g.returncode == 0 and 'HAILSHOT_GL_OK' in g.stdout,
      g.stdout + g.stderr)
bogus = dict(os.environ)
bogus['HAILSHOT_GL_LIB'] = '/nonexistent/orp::/also/bogus'
g2 = subprocess.run(['python3', '/app/gloss/peregrine.py'],
                    capture_output=True, text=True, env=bogus)
check('osmesa_bogus_env_fallback', g2.returncode == 0 and 'HAILSHOT_GL_OK' in g2.stdout,
      g2.stdout + g2.stderr)

if probs:
    for p in probs:
        print('FAIL:', p)
    sys.exit(1)
print('ALL_VERIFIER_GATES_OK')
PY
then reward=1
fi

echo "$reward" > /logs/verifier/reward.txt