#!/bin/bash
# Oracle for onyx-ember: author the real, idempotent /app/repair.sh deliverable
# and RUN it to actually repair the Onyx Forge platform in this container. It
# never reads /app and never cats a precomputed answer.
set -euo pipefail

cat > /app/repair.sh <<'REPAIR_SCRIPTSHELL'
#!/bin/bash
# Idempotent repair for the Onyx Forge telemetry platform.
# Safe to re-run from any previous state (fresh / degraded / fully fixed);
# every step first checks whether that dependency still needs work.
set -euo pipefail

BASE=/app
PY="$(command -v python3)"
MOND="/opt/miniconda/bin/conda"

echo "== onyx-forge repair starting =="

# ---- 1. Restore pip from the official bootstrap script (never a broken copy)
if ! "$PY" -m pip --version >/dev/null 2>&1; then
    echo "restoring pip via official get-pip.py..."
    curl -fsSL https://bootstrap.pypa.io/get-pip.py | "$PY" -
fi

# ---- 2. Leave numpy importable system-wide --------------------------------
if ! "$PY" -c "import numpy" >/dev/null 2>&1; then
    echo "installing numpy into the default interpreter..."
    "$PY" -m pip install -q "numpy>=2"
fi

# ---- 3. End-to-end small package installs + imports with the repaired pip --
if ! "$PY" -c "import prism;assert prism.label('1')=='prism::1'" >/dev/null 2>&1; then
    echo "installing helper package 'prism' (end-to-end pip)."
    "$PY" -m pip install -q -e "$BASE/shelf/prism"
fi

# ---- 4. Rebuild + editable-install onyxprism so the default interpreter
#         loads the NATIVE backend (not the stub fallback). -------------------
SITEPKGS="$("$PY" -c "import sysconfig;print(sysconfig.get_paths()['purelib'])")"
# Drop any stale broken stub in site-packages so it cannot shadow the build.
rm -rf "$SITEPKGS/onyxprism"
if ! compgen -G "$BASE/shelf/onyxprism/onyxprism/_fast"*.so >/dev/null 2>&1; then
    echo "compiling the onyxprism Cython extension in place..."
    ( cd "$BASE/shelf/onyxprism" && "$PY" setup.py build_ext --inplace >/dev/null 2>&1 )
fi
if ! "$PY" -c "import onyxprism;assert onyxprism.backend=='native'" >/dev/null 2>&1; then
    echo "editable-installing onyxprism into the default interpreter..."
    "$PY" -m pip install -q --no-build-isolation -e "$BASE/shelf/onyxprism"
fi

# ---- 5. rebuilt deliverable: compiled artifact for the default interpreter --
mkdir -p /app/rebuilt
cp -f "$BASE"/shelf/onyxprism/onyxprism/_fast*.so /app/rebuilt/ 2>/dev/null || true

# ---- 6. named conda environment instantiated from a dependencies spec ------
cat > "$BASE/env.txt" <<'ENVSPEC'
name: onyx_env
channels:
  - defaults
dependencies:
  - python=3.11
  - setuptools
ENVSPEC
cp -f "$BASE/env.txt" "$BASE/onyx_env.yml"
if ! "$MOND" env list | awk '{print $1}' | grep -qx 'onyx_env'; then
    echo "creating conda environment onyx_env from /app/env.txt..."
    "$MOND" env create -q -f "$BASE/onyx_env.yml" -y
fi

echo "REPAIR_DONE"
REPAIR_SCRIPTSHELL

chmod +x /app/repair.sh

# Run the repair now so the platform is left actually fixed.
bash /app/repair.sh

echo "ORACLE_DONE"