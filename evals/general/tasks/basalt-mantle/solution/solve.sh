#!/bin/bash
# Oracle for basalt-mantle. This repairs the environment for real (running the
# fixes), and leaves behind the two required deliverables:
#    /app/repair.sh   - a reusable, idempotent repair script
#    /app/verify.py   - a script that re-checks every repaired capability
# It never reads /tests and never cats a precomputed answer.
set -euo pipefail

cat > /app/repair.sh <<'RSCRIPT'
#!/bin/bash
# Idempotent repair for the Shale Forge platform (basalt-mantle).
# Safe to re-run: every step guards on whether it is already applied.
set -euo pipefail
PY="$(command -v python3)"

# ---- 1) default-interpreter package `kether`: install the working build ----
if ! "$PY" -c "import kether" 2>/dev/null; then
  "$PY" -m pip install --no-build-isolation --no-deps -q /app/shelf/kether
fi

# ---- 2) edited package `spect`: reinstall the edited tree so its suite passes --
VER="$("$PY" -c "import spect;print(getattr(spect,'__version__',''))" 2>/dev/null || true)"
if [ "$VER" != "2.1.0" ]; then
  "$PY" -m pip install --no-build-isolation --no-deps --upgrade -q /app/shelf/spect
fi

# ---- 3) cython/numpy2 `pyros`: port the build off numpy.distutils and rebuild ----
cat > /app/shelf/pyros/setup.py <<'PYSETUP'
import os
from setuptools import setup, Extension
from Cython.Build import cythonize
here = os.path.abspath(os.path.dirname(__file__))
setup(
    name='pyros', version='2.0.0',
    ext_modules=cythonize(
        [Extension('pyros', sources=[os.path.join(here, 'pyros.pyx')],
                   include_dirs=[here])],
        language_level=3),
    zip_safe=False,
)
PYSETUP
if ! "$PY" -c "import pyros" 2>/dev/null; then
  ( cd /app/shelf/pyros && "$PY" setup.py build_ext --inplace >/dev/null 2>&1 )
  SITE="$("$PY" -c "import sysconfig;print(sysconfig.get_paths()['purelib'])")"
  cp /app/shelf/pyros/pyros*.so "$SITE"/
fi

# ---- 4) OSMesa loader library ----
mkdir -p /opt/osp/gl/lib
LIB="$(find /usr/lib -name 'libOSMesa.so.8*' 2>/dev/null | head -1)"
if [ -z "$LIB" ]; then
  LIB="$(find /usr -name 'libOSMesa.so.8*' 2>/dev/null | head -1)"
fi
if [ -n "$LIB" ] && [ ! -e /opt/osp/gl/lib/libOSMesa.so ]; then
  cp "$LIB" /opt/osp/gl/lib/libOSMesa.so
fi

# ---- 5) interpreter shim + Rscript into settings.json ----
SHIM="$("$PY" -c "import sys;print(sys.executable)")"
if command -v Rscript >/dev/null 2>&1; then
  RSCRIPT="$(command -v Rscript)"
else
  RSCRIPT="/usr/bin/Rscript"
fi
"$PY" - <<PYEOF
import json
p = '/app/ima/runner/settings.json'
d = json.load(open(p))
d['python_shim'] = '$SHIM'
d['rscript'] = '$RSCRIPT'
open(p, 'w').write(json.dumps(d, indent=2) + '\n')
PYEOF

# ---- 6) R Jupyter kernel registration (ir & analysis pkgs preinstalled) ----
KS=/root/.local/share/jupyter/kernels/rcausal/kernel.json
if [ ! -e "$KS" ] && command -v Rscript >/dev/null 2>&1; then
  Rscript --vanilla -e 'IRkernel::installspec(name="rcausal", displayname="R causal analyst (shale)", user=TRUE)' >/dev/null 2>&1 || true
fi

echo "REPAIR_DONE"
RSCRIPT

chmod +x /app/repair.sh

# Run the real repair now (this is where the environment actually gets fixed).
bash /app/repair.sh

# Deliver the verification script /app/verify.py.
cat > /app/verify.py <<'VPY'
#!/usr/bin/env python3
"""verify.py: re-run every originally-failing check for the Shale platform.

Exits 0 (and prints ALL_OK) only if every repaired capability is in place.
"""
import json
import os
import subprocess
import sys

FAILS = []
MSG = []


def ok(name, cond):
    MSG.append(('PASS' if cond else 'FAIL') + ' ' + name)
    if not cond:
        FAILS.append(name)


# 1) default-interpreter package
try:
    import kether
    ok('kether_import_works', abs(kether.flows([1.0, 2.0, 3.0]) - 6.0) < 1e-9)
except Exception as exc:  # noqa: BLE001
    MSG.append('FAIL kether_import_works  (%s)' % exc)
    FAILS.append('kether_import_works')

# 2) edited package reinstall
try:
    import spect
    ok('spect_edited_installed', getattr(spect, '__version__', '') == '2.1.0')
    ok('spect_math', spect.prefix_digest('ab') == '00c3')
except Exception as exc:  # noqa: BLE001
    MSG.append('FAIL spect_edited_installed  (%s)' % exc)
    FAILS.append('spect_edited_installed')

# 3) cython/numpy 2.x extension
try:
    import numpy
    import pyros
    ok('pyros_numpy2', numpy.__version__.startswith('2.'))
    ok('pyros_ring', abs(pyros.ring(2) - 5.0) < 1e-9)
    ok('pyros_converge', abs(pyros.converge([2.0, 2.0]) - 4.0) < 1e-9)
except Exception as exc:  # noqa: BLE001
    MSG.append('FAIL pyros_build_readiness  (%s)' % exc)
    FAILS.append('pyros_build_readiness')

# 4) OSMesa loader
g = subprocess.run(['python3', '/app/gloss/fern_gl.py'],
                   capture_output=True, text=True)
ok('osmesa_loader', g.returncode == 0 and 'OSMESA_OK' in g.stdout)

# 5) interpreter shim in settings + runner
cfg = json.load(open('/app/ima/runner/settings.json'))
shim = (cfg.get('python_shim') or '').strip()
ok('python_shim_set', bool(shim))
ok('python_shim_exec', bool(shim) and os.path.isfile(shim) and os.access(shim, os.X_OK))
sp = subprocess.run(['python3', '/app/ima/runner/spire.py',
                     '/app/ima/runner/target_probe.py'],
                    capture_output=True, text=True)
ok('spire_cprofile_run', sp.returncode == 0 and 'SPIRE_OK' in sp.stdout)

# 6) R statistical runtime self-test
rs = (cfg.get('rscript') or '').strip()
ok('rscript_set', bool(rs) and os.path.isfile(rs))
rp = subprocess.run(['python3', '/app/ima/runner/rself.py'],
                    capture_output=True, text=True)
ok('r_self_test', rp.returncode == 0 and 'R_SELFTEST' in rp.stdout)

# 7) R Jupyter kernel + analysis package
ks = '/root/.local/share/jupyter/kernels/rcausal/kernel.json'
k_ok = os.path.isfile(ks)
argv0 = ''
if k_ok:
    try:
        kd = json.load(open(ks))
        argv0 = (kd.get('argv') or [''])[0]
    except Exception:  # noqa: BLE001
        argv0 = ''
ok('rcausal_kernel_registered', k_ok and bool(argv0) and os.path.isfile(argv0))
kl = subprocess.run(['jupyter', 'kernelspec', 'list'],
                    capture_output=True, text=True)
ok('rcausal_kernel_listed', 'rcausal' in kl.stdout)

print('\n'.join(MSG))
if FAILS:
    print('NOT_OK fails=%s' % ','.join(FAILS))
    sys.exit(1)
print('ALL_OK')
VPY
chmod +x /app/verify.py

# Sanity: confirm the repair actually took (best-effort; not reading /tests).
"$(command -v python3)" /app/verify.py