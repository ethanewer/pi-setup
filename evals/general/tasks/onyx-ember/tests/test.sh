#!/bin/bash
# Verifier for onyx-ember (executes-deliverable).
#
# EXECUTES the /app/repair.sh deliverable from the pristine state and then from
# several genuinely different degraded pre-existing states (seed1..seed3), and
# after each run re-checks the whole platform: native Cython backend for the
# default interpreter, checksum agreement with the pure fallback on unseen
# inputs, the targeted async-fs suite, pip restored from the bootstrap (plus a
# fresh package), numpy importable, the named conda env from a spec, and the
# /app/rebuilt compiled artifact loading + behaving correctly.
# Writes REWARD (0/1) to /logs/verifier/reward.txt; runs as root.
set -u
mkdir -p /logs/verifier
reward=0
# Crash-proof: always leave a numeric reward behind, even if a hidden-seed
# run dies midway (network hiccup, conda timeout, ...) before the final echo.
trap 'echo "$reward" > /logs/verifier/reward.txt' EXIT
BASE=/app

cat > /tmp/verify_spec.py <<'PYV'
import glob, importlib.util, json, os, re, subprocess, sys

HD = '/tests/hidden'
fail = []


def check(name, cond, detail=''):
    if not cond:
        fail.append('%s <%s>' % (name, detail))


# ---- 1. default-interpreter onyxprism: native backend + digest correctness --
try:
    import onyxprism as ox
    check('onyx_backend_native', ox.backend == 'native', getattr(ox, 'backend', None))
    check('onyx_visible_hex', '%08x' % ox.checksum(b'onyx-forge') == '350f164b',
          '%08x' % ox.checksum(b'onyx-forge'))
    cases = json.load(open(os.path.join(HD, 'checksum_cases.json')))['inputs']
    for i, case in enumerate(cases):
        s = case['input']
        try:
            nat = ox.checksum(s)
            pure = ox._pure.checksum(s)
            check('native_hidden_%d' % i, '%08x' % nat == case['expected'], ('%08x' % nat, s))
            check('native_pure_agree_%d' % i, nat == pure, (nat, pure))
        except Exception as exc:
            check('native_hidden_%d' % i, False, str(exc))
except Exception as exc:
    check('onyx_import', False, str(exc))

# ---- 2. targeted async-filesystem unit suite --------------------------------
pt = subprocess.run(['python3', '-m', 'pytest', '-q', '/app/shelf/onyxprism/tests'],
                    capture_output=True, text=True)
out = pt.stdout + pt.stderr
check('asyncfs_pytest_green', pt.returncode == 0 and 'passed' in out and 'failed' not in out,
      (out or '')[-300:])

# ---- 3. pip restored from the bootstrap + fresh small package installs ------
pv = subprocess.run(['python3', '-m', 'pip', '--version'], capture_output=True, text=True)
check('pip_restored', pv.returncode == 0 and 'pip' in pv.stdout, pv.stdout + pv.stderr)
pr = subprocess.run(['python3', '-c', 'import prism;assert prism.label("z")=="prism::z";print(prism.label("z"))'],
                    capture_output=True, text=True)
check('prism_imports', pr.returncode == 0 and pr.stdout.strip() == 'prism::z',
      (pr.stdout + pr.stderr)[-300:])

# ---- 4. numpy importable system-wide ----------------------------------------
nv = subprocess.run(['python3', '-c', 'import numpy;print(numpy.__version__)'],
                    capture_output=True, text=True)
check('numpy_systemwide', nv.returncode == 0, (nv.stdout + nv.stderr)[-200:])

# ---- 5. conda env instantiated from the spec --------------------------------
ev = subprocess.run(['/opt/miniconda/bin/conda', 'env', 'list'], capture_output=True, text=True)
check('conda_env_present', 'onyx_env' in (ev.stdout + ev.stderr), ev.stdout + ev.stderr)
cr = subprocess.run(['/opt/miniconda/bin/conda', 'run', '-n', 'onyx_env', 'python3', '-c', 'print(1+1)'],
                    capture_output=True, text=True)
check('conda_run_works', cr.returncode == 0 and cr.stdout.strip() == '2',
      (cr.stdout + cr.stderr)[-300:])

# ---- 6. /app/env.txt spec artifact + conda spec applicability --------------
try:
    envtxt = open('/app/env.txt').read()
except Exception:
    envtxt = ''
# The instruction promises a spec named `onyx_env` whose python is PINNED to a
# specific CPython version; it deliberately leaves the exact version to the
# agent ('Choose a small, lean set of dependencies (a specific CPython version
# plus setuptools is enough)'). Accept any contiguous pinned version.
pinned_py = bool(re.search(r'python\s*[=: ]+\s*\d+\.\d+', envtxt))
check('envtxt_spec', 'name: onyx_env' in envtxt and pinned_py,
      (envtxt or '')[:200])

# ---- 7. /app/rebuilt compiled artifact loads and computes correctly --------
so = glob.glob('/app/rebuilt/_fast*.so')
check('rebuilt_exists', len(so) == 1, so)
if so:
    try:
        spec = importlib.util.spec_from_file_location('_fast', so[0])
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        check('rebuilt_checksum', '%08x' % mod.checksum(b'onyx-forge') == '350f164b',
              '%08x' % mod.checksum(b'onyx-forge'))
    except Exception as exc:
        check('rebuilt_load', False, str(exc))

if fail:
    for f in fail:
        print('SPEC-FAIL: ' + f)
    sys.exit(1)
print('SPEC-OK')
sys.exit(0)
PYV

# Execute the deliverable and check the full spec.
run_case() {
    local label="$1"
    local slug="$(echo "$label" | tr '/:' '__')"
    if [ ! -f "$BASE/repair.sh" ]; then
        echo "FAIL[$label]: /app/repair.sh missing"
        return 1
    fi
    if ! bash "$BASE/repair.sh" >"/tmp/repair_$slug.log" 2>&1; then
        echo "FAIL[$label]: repair.sh exit != 0: $(tail -2 /tmp/repair_$slug.log 2>/dev/null)"
        return 1
    fi
    if ! python3 /tmp/verify_spec.py; then
        return 1
    fi
    echo "OK[$label]"
    return 0
}

all_ok=0
run_case visible && all_ok=1

# Hidden cases: different pre-existing degraded states; repair.sh must re-fix
# each and the full spec must pass again.
if [ -d /tests/hidden ]; then
    for c in $(ls /tests/hidden); do
        [ "$c" = "checksum_cases.json" ] && continue
        seed="/tests/hidden/$c/seed.sh"
        if [ ! -f "$seed" ]; then
            echo "FAIL[hidden/$c]: missing seed.sh"
            all_ok=0
            continue
        fi
        if ! bash "$seed" >/tmp/seed_$c.log 2>&1; then
            echo "FAIL[hidden/$c]: seed failed: $(tail -1 /tmp/seed_$c.log 2>/dev/null)"
            all_ok=0
            continue
        fi
        run_case "hidden/$c" || all_ok=0
    done
else
    echo "FAIL: no /tests/hidden directory"
    all_ok=0
fi

[ "$all_ok" -eq 1 ] && reward=1
echo "$reward" > /logs/verifier/reward.txt
exit 0