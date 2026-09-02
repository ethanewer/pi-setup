#!/usr/bin/env bash
# Harbor Gasket -- full solution.
# Provisions the venv, builds swellkit from the shipped source, pins the exact
# Node toolchain + hydra plugin, makes torch(CPU)+onnxruntime coexist, and
# stands up a local package-index server. Every deliverable is produced by
# doing the real work.
set -euo pipefail

log() { echo "[solve] $*" >&2; }

# ---------------------------------------------------------------------------
# Task 1 -- venv + swellkit from source
# ---------------------------------------------------------------------------
log "creating /app/venv"
python3 -m venv /app/venv

log "building swellkit from /app/src"
/app/venv/bin/pip install -q --no-cache-dir /app/src
test -d /app/venv/lib/python3.12/site-packages/swellkit \
  || { echo "swellkit missing from venv site-packages" >&2; exit 1; }

log "running import check"
/app/venv/bin/python /app/kit/import_check.py > /app/import-check.txt
grep -q "HARBOR_GASKET_IMPORT_CHECK" /app/import-check.txt \
  || { echo "import check marker missing" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Task 3 dependencies (installed now so torch is present for the toolchain
# and later for the coexist check)
# ---------------------------------------------------------------------------
log "installing CPU-only torch (pinned) + onnxruntime + onnx"
/app/venv/bin/pip install -q --no-cache-dir \
  --extra-index-url https://download.pytorch.org/whl/cpu \
  "torch==2.5.1+cpu"
/app/venv/bin/pip install -q --no-cache-dir \
  "onnxruntime==1.29.0" "onnx"

# ---------------------------------------------------------------------------
# Task 3 -- deliverable /app/dl-coexist.py + /app/frameworks-ok.txt
# ---------------------------------------------------------------------------
cat > /app/dl-coexist.py <<'PY'
#!/usr/bin/env python3
"""Harbor Gasket CPU coexistence check: torch (CPU-only) + onnxruntime.

Usage:
    /app/venv/bin/python3 /app/dl-coexist.py                default net
    /app/venv/bin/python3 /app/dl-coexist.py --spec FILE    custom dims

Prints exactly one marker line to stdout, writes the same line to
/app/frameworks-ok.txt, exits 0 on success / 2 on a malformed spec.
"""
import io
import json
import sys

import numpy as np
import torch
import torch.nn as nn


DEFAULT = {"seed": 7, "in": 6, "hid": 12, "out": 3, "batch": 4}
MARKER_PREFIX = "DL_COEXIST_OK"


def build_net(in_dim, hid_dim, out_dim):
    return nn.Sequential(
        nn.Linear(in_dim, hid_dim),
        nn.ReLU(),
        nn.Linear(hid_dim, out_dim),
    )


def run_case(cfg):
    import onnxruntime
    from torch.onnx import export as to_export

    if torch.cuda.is_available():
        sys.stderr.write("COEXIST-FAIL: CUDA is available but the venv must be CPU-only\n")
        return None
    torch.manual_seed(cfg["seed"])
    m = build_net(cfg["in"], cfg["hid"], cfg["out"])
    x = torch.randn(cfg["batch"], cfg["in"])
    y = m(x)
    if not bool(torch.isfinite(y).all()):
        sys.stderr.write("COEXIST-FAIL: non-finite torch output\n")
        return None

    buf = io.BytesIO()
    to_export(
        m, x, buf,
        input_names=["in"], output_names=["out"],
        opset_version=14,
    )
    buf.seek(0)
    session = onnxruntime.InferenceSession(
        buf.read(), providers=["CPUExecutionProvider"]
    )
    if session.get_providers() != ["CPUExecutionProvider"]:
        sys.stderr.write("COEXIST-FAIL: onnxruntime is not CPU-execution-only\n")
        return None
    z = session.run(None, {"in": x.numpy()})[0]
    diff = float(np.abs(z - y.detach().numpy()).max())
    if diff > 1e-3:
        sys.stderr.write("COEXIST-FAIL: torch/onnx mismatch maxdiff=%g\n" % diff)
        return None
    return diff


def main():
    cfg = dict(DEFAULT)
    if "--spec" in sys.argv:
        idx = sys.argv.index("--spec")
        if idx + 1 >= len(sys.argv):
            sys.stderr.write("COEXIST-ERROR: --spec requires a FILE argument\n")
            return 2
        try:
            spec = json.load(open(sys.argv[idx + 1]))
        except Exception as exc:
            sys.stderr.write("COEXIST-ERROR: cannot read spec: %s\n" % exc)
            return 2
        need = {"seed", "in", "hid", "out", "batch"}
        if not isinstance(spec, dict) or not need.issubset(spec):
            sys.stderr.write("COEXIST-ERROR: spec must be an object with keys %s\n"
                             % sorted(need))
            return 2
        for key, val in spec.items():
            ok = isinstance(val, int) and not isinstance(val, bool) and val > 0
            if not ok:
                sys.stderr.write("COEXIST-ERROR: %s must be a positive int\n" % key)
                return 2
        cfg.update(spec)

    diff = run_case(cfg)
    if diff is None:
        return 1
    line = "%s torch=%s ort=%s maxdiff=%.6e" % (
        MARKER_PREFIX, torch.__version__, _ort_version(), diff,
    )
    sys.stdout.write(line + "\n")
    with open("/app/frameworks-ok.txt", "w") as fh:
        fh.write(line + "\n")
    return 0


def _ort_version():
    import onnxruntime

    return onnxruntime.__version__


if __name__ == "__main__":
    sys.exit(main())
PY
chmod +x /app/dl-coexist.py
log "running dl-coexist.py"
/app/venv/bin/python3 /app/dl-coexist.py

# ---------------------------------------------------------------------------
# Task 2 -- deliverable /app/pin-toolchain.sh + version.txt + plugin
# ---------------------------------------------------------------------------
cat > /app/pin-toolchain.sh <<'SH'
#!/usr/bin/env bash
# Harbor Gasket -- pin the exact toolchain (Node v20.19.3) and the
# hydra-submitit-launcher plugin (1.2.0). Idempotent and re-runnable from a
# wiped /app/toolchain.
set -euo pipefail

TOOL=/app/toolchain
RELEASE=/app/releases/node-v20.19.3-linux-x64.tar.xz
NODE_DIR=$TOOL/node-v20.19.3-linux-x64
NODE_BIN=$NODE_DIR/bin/node
PLUGIN="hydra-submitit-launcher==1.2.0"
VFILE=/app/toolchain/version.txt

mkdir -p "$TOOL"

if [ ! -x "$NODE_BIN" ]; then
    rm -rf "$NODE_DIR"
    tar -xJf "$RELEASE" -C "$TOOL"
fi
[ -x "$NODE_BIN" ] || { echo "pin-toolchain: node binary missing" >&2; exit 1; }

/app/venv/bin/pip install -q --no-cache-dir "$PLUGIN"
/app/venv/bin/python -c "import hydra_plugins.hydra_submitit_launcher" \
  || { echo "pin-toolchain: hydra submitit plugin not importable" >&2; exit 1; }

# Live-reported exact version, then write the report.
NODE_VER=$("$NODE_BIN" --version)
printf 'node=%s\nplugin=%s\n' "$NODE_VER" "$PLUGIN" > "$VFILE"

echo "pin-toolchain: node $NODE_VER, plugin $PLUGIN -> $VFILE"
SH
chmod +x /app/pin-toolchain.sh
log "running pin-toolchain.sh"
bash /app/pin-toolchain.sh

# ---------------------------------------------------------------------------
# Task 4 -- deliverable /app/serve-index.sh + package-dir + client install
# ---------------------------------------------------------------------------
cat > /app/serve-index.sh <<'SH'
#!/usr/bin/env bash
# Harbor Gasket -- local package-index server on 127.0.0.1:8765 serving the
# built swellkit artifact. Idempotent: a re-run always leaves a live server.
set -euo pipefail

PORT=8765
PKG=/app/package-dir
PIDF=/app/.serve.pid

mkdir -p "$PKG/swellkit"

# Build the wheel from the shipped source each run.
rm -rf /tmp/hgwheel && mkdir -p /tmp/hgwheel
/app/venv/bin/pip wheel -q --no-deps --wheel-dir /tmp/hgwheel /app/src
WHEEL=$(ls /tmp/hgwheel/swellkit-2.4.1-*.whl 2>/dev/null | head -1)
[ -n "$WHEEL" ] || { echo "serve-index: no swellkit wheel produced" >&2; exit 1; }

# Stage per-project layout (PEP 503): packages live in <project>/ subdirs.
rm -f "$PKG/swellkit/"*.whl
cp -f "$WHEEL" "$PKG/swellkit/"

# Root index.html: link to each project subdirectory.
{
    echo "<!DOCTYPE html>"
    echo "<html><head><title>Harbor Gasket package index</title></head><body>"
    echo "<a href=\"swellkit/\">swellkit</a>"
    echo "</body></html>"
} > /app/package-dir/index.html

# Project index.html: anchor per staged wheel file.
names=$(cd "$PKG/swellkit" && ls *.whl)
{
    echo "<!DOCTYPE html>"
    echo "<html><head><title>Links for swellkit</title></head><body>"
    for n in $names; do
        echo "<a href=\"$n\">$n</a>"
    done
    echo "</body></html>"
} > "$PKG/swellkit/index.html"

# Stop a previous instance tracked in the pidfile (idempotent restart).
if [ -f "$PIDF" ]; then
    OPID=$(cat "$PIDF" 2>/dev/null || true)
    if [ -n "$OPID" ] && kill -0 "$OPID" 2>/dev/null; then
        kill "$OPID" 2>/dev/null || true
        for _ in $(seq 1 30); do kill -0 "$OPID" 2>/dev/null || break; sleep 0.1; done
    fi
fi
nohup python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$PKG" \
    >/tmp/hg-http.log 2>&1 &
echo $! > "$PIDF"

for _ in $(seq 1 40); do
    if curl -sf "http://127.0.0.1:$PORT/" >/dev/null 2>&1; then
        echo "serve-index: live on http://127.0.0.1:$PORT ($PORT)"
        exit 0
    fi
    sleep 0.25
done
echo "serve-index: server did not come up on port $PORT" >&2
exit 1
SH
chmod +x /app/serve-index.sh
log "running serve-index.sh"
bash /app/serve-index.sh

log "client install from live index"
rm -rf /tmp/hgclient && mkdir -p /tmp/hgclient
{
    /app/venv/bin/pip install --no-cache-dir --target /tmp/hgclient --no-deps \
        --index-url http://127.0.0.1:8765 --trusted-host 127.0.0.1 \
        "swellkit==2.4.1" 2>&1
    echo "---"
    PYTHONPATH=/tmp/hgclient python3 -c "import swellkit; print('client import', swellkit.__version__)"
    echo "---"
    echo "CLIENT_INSTALL_OK version=2.4.1 index=http://127.0.0.1:8765"
} > /app/client-install.log 2>&1
grep -q "CLIENT_INSTALL_OK version=2.4.1" /app/client-install.log \
  || { echo "client install failed" >&2; tail -20 /app/client-install.log >&2; exit 1; }
PYTHONPATH=/tmp/hgclient python3 -c "import swellkit; assert swellkit.__version__=='2.4.1'"

echo "HARBOR-GASKET SOLVE OK"
