#!/usr/bin/env bash
# Harbor Gasket verifier. Runs as root after the agent finishes; /tests is
# read-only. Executes every deliverable (real /app paths), drives the hidden
# cases from /tests/hidden, and writes 1 or 0 to /logs/verifier/reward.txt.
set -uo pipefail

REWARD_FILE=/logs/verifier/reward.txt
mkdir -p "$(dirname "$REWARD_FILE")"

fail() { echo "VERIFY-FAIL: $*" >&2; echo 0 > "$REWARD_FILE"; exit 1; }
okay() { echo "REWARD-OK: harbor-gasket all checks passed" >&2; echo 1 > "$REWARD_FILE"; exit 0; }

log() { echo "[test] $*" >&2; }

# ===========================================================================
# 0. Deliverable presence (negative control must fail here, fast)
# ===========================================================================
for f in /app/venv /app/import-check.txt /app/pin-toolchain.sh \
         /app/toolchain/version.txt /app/dl-coexist.py \
         /app/frameworks-ok.txt /app/serve-index.sh \
         /app/package-dir/index.html /app/client-install.log; do
  [ -e "$f" ] || fail "missing deliverable: $f"
done
[ -x /app/pin-toolchain.sh ]  || fail "/app/pin-toolchain.sh not executable"
[ -x /app/dl-coexist.py ]     || fail "/app/dl-coexist.py not executable"
[ -x /app/serve-index.sh ]    || fail "/app/serve-index.sh not executable"
[ -d /app/venv/lib/python3.12/site-packages/swellkit ] \
  || fail "swellkit not installed in /app/venv site-packages"
/app/venv/bin/python -c "import ast; ast.parse(open('/app/dl-coexist.py').read())" \
  || fail "/app/dl-coexist.py has a syntax error"
bash -n /app/pin-toolchain.sh || fail "/app/pin-toolchain.sh bash syntax error"
bash -n /app/serve-index.sh   || fail "/app/serve-index.sh bash syntax error"

# ===========================================================================
# 1. Framework competency (C-cafd4691): rebuild from source + hidden API cases
# ===========================================================================
log "framework: re-running shipped import check and byte-comparing"
STORED_IMP=$(cat /app/import-check.txt)
FRESH_IMP=$(/app/venv/bin/python /app/kit/import_check.py)
[ "$STORED_IMP" == "$FRESH_IMP" ] || fail "import-check.txt does not byte-match a fresh re-run"
printf '%s\n' "$FRESH_IMP" | grep -q "^HARBOR_GASKET_IMPORT_CHECK framework=swellkit version=2.4.1" \
  || fail "import-check.txt missing the expected marker line"

# Independent numeric cross-check of the import report.
/app/venv/bin/python - "$FRESH_IMP" <<'PY' || fail "import-check numbers wrong"
import math, sys
report = sys.argv[1]
def height(t, text):
    rad = math.pi / 180.0
    tot = 0.0
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        p = [x.strip() for x in line.split(",")]
        tot += float(p[1]) * math.cos(2.0*math.pi*t/float(p[2]) + float(p[3])*rad)
    return tot
sample = ("# Halcyon Reach tide table\n\nM2,1.2,12.4206012,0\nS2,0.5,12.0,30.0\n"
          "K1,0.3,23.934472,120.0\n")
ref_h12 = height(12.0, sample)
ref_rms = math.sqrt(sum(x*x for x in (1.0,-3.0,4.0))/3.0)
ref_ms = (20.0+30.0)/2.0
ref_km = None
# forecast_file reads the shipped /app/data/constituents.csv -- recompute from it
f0 = height(0.0, open('/app/data/constituents.csv').read())
# recompute haversine independently
lon1,lat1,lon2,lat2 = -122.42,37.77,-73.99,40.71
p1,l1,p2,l2 = (math.radians(x) for x in (lat1,lon1,lat2,lon2))
a=(math.sin((p2-p1)/2.0)**2 + math.cos(p1)*math.cos(p2)*math.sin((l2-l1)/2.0)**2)
ref_km = 2.0*6371.0088*math.asin(math.sqrt(a))
def fmt(x): return ("%.9f" % x)
def fmt12(x): return ("%.12f" % x)
need = {
 "height_hours(12.0)="+fmt(ref_h12): True,
 "forecast_file(0.0)="+fmt(f0): True,
 "rms_amplitude="+fmt12(ref_rms): True,
 "mean_slice="+fmt12(ref_ms): True,
 "haversine_km="+fmt(ref_km): True,
 "core_rms="+fmt12(4.0): True,
}
for tok in report.splitlines():
    for key in need:
        if key in tok:
            need[key] = False
bad = [k for k,v in need.items() if v]
assert not bad, bad
print("independent import-check numbers ok")
PY

log "framework: rebuilding swellkit from /app/src in a fresh venv"
rm -rf /tmp/rbvenv
python3 -m venv /tmp/rbvenv >/dev/null 2>&1 \
  || fail "cannot create rebuild venv"
/tmp/rbvenv/bin/pip install -q --no-cache-dir /app/src >/tmp/rb_build.log 2>&1 \
  || fail "rebuild pip install failed: $(tail -2 /tmp/rb_build.log)"

cp /tests/hidden/framework/cases.json /tmp/rb_cases.json
/tmp/rbvenv/bin/python - <<'PY' || fail "hidden framework API cases failed (see /tmp/rb_fails.log)"
import json, sys
cases = json.load(open("/tmp/rb_cases.json"))
import swellkit
from swellkit import diagnostics, grid
import swellkit._core as core
fails = []
for c in cases["tide"]:
    try:
        got = swellkit.height_hours(c["hours"], c["text"])
        if c.get("expect_error"):
            fails.append((c["id"], "expected ValueError but got value %r" % got))
        elif abs(got - c["expect"]) > c.get("tol", 1e-9):
            fails.append((c["id"], got, c["expect"]))
    except ValueError:
        if not c.get("expect_error"):
            fails.append((c["id"], "unexpected ValueError"))
for c in cases["rms"]:
    got = diagnostics.rms_amplitude(c["vals"])
    if abs(got - c["expect"]) > c.get("tol", 1e-9):
        fails.append((c["id"], got, c["expect"]))
for c in cases["grid"]:
    got = grid.haversine_km(*c["args"])
    if abs(got - c["expect"]) > c.get("tol", 1e-6):
        fails.append((c["id"], got, c["expect"]))
try:
    for c in cases["rms"]:
        got = core.rms(c["vals"])
        if abs(got - c["expect"]) > c.get("tol", 1e-9):
            fails.append(("core_" + c["id"], got, c["expect"]))
except Exception as exc:
    fails.append(("core_import", str(exc)))
if fails:
    open("/tmp/rb_fails.log", "w").write("\n".join(repr(f) for f in fails))
    sys.exit(1)
print("hidden framework cases: all %d pass" % (
    len(cases["tide"]) + len(cases["rms"]) + len(cases["grid"])))
PY

# ===========================================================================
# 2. Toolchain pin (C-da851430): wipe-and-reprovision + live probes
# ===========================================================================
log "toolchain: reading hidden expectations"
TOOL_QUERY=$(python3 -c "import json;d=json.load(open('/tests/hidden/toolchain/query.json'));print(d['node'],d['node_dir'],d['plugin'],d['plugin_version'],d['plugin_pin'])")
read -r EXPECT_NODE EXPECT_NODE_DIR EXPECT_PLUGIN EXPECT_PLUGIN_VER EXPECT_PLUGIN_PIN <<< "$TOOL_QUERY"

log "toolchain: wiping /app/toolchain and re-running pin-toolchain.sh"
rm -rf /app/toolchain
bash /app/pin-toolchain.sh >/tmp/pt.out 2>/tmp/pt.err \
  || fail "pin-toolchain.sh re-run failed: $(tail -1 /tmp/pt.err)"
NODE_BIN="/app/toolchain/$EXPECT_NODE_DIR/bin/node"
[ -x "$NODE_BIN" ] || fail "node interpreter not at $NODE_BIN"
LIVE_NODE=$("$NODE_BIN" --version) || fail "node --version failed"
[ "$LIVE_NODE" == "$EXPECT_NODE" ] || fail "node version $LIVE_NODE != expected $EXPECT_NODE"

PLUGIN_VER=$(/app/venv/bin/python -m pip show "$EXPECT_PLUGIN" 2>/dev/null \
  | sed -n 's/^Version: *//p')
[ "$PLUGIN_VER" == "$EXPECT_PLUGIN_VER" ] || fail "plugin version $PLUGIN_VER != $EXPECT_PLUGIN_VER"
/app/venv/bin/python -c "import hydra_plugins.hydra_submitit_launcher" \
  || fail "hydra submitit plugin not importable"

VFILE=/app/toolchain/version.txt
VNODE=$(sed -n '1s/^node=//p' "$VFILE")
VPLUG=$(sed -n '2s/^plugin=//p' "$VFILE")
[ "$VNODE" == "$EXPECT_NODE" ]     || fail "version.txt node line is '$VNODE'"
[ "$VPLUG" == "$EXPECT_PLUGIN_PIN" ] || fail "version.txt plugin line is '$VPLUG'"
[ $(wc -l < "$VFILE") -eq 2 ] || fail "version.txt must have exactly 2 lines"

# ===========================================================================
# 3. DL coexistence (C-b46437b6): CPU-only torch + onnxruntime, no clamp
# ===========================================================================
log "dl: re-running /app/dl-coexist.py"
STORED_DL=$(cat /app/frameworks-ok.txt)
DL_OUT=$(/app/venv/bin/python3 /app/dl-coexist.py) || fail "dl-coexist.py default run failed"
[ "$STORED_DL" == "$DL_OUT" ] || fail "frameworks-ok.txt != fresh re-run of dl-coexist.py"
[ "$(cat /app/frameworks-ok.txt)" == "$DL_OUT" ] || fail "frameworks-ok.txt not rewritten by the live re-run"
printf '%s\n' "$DL_OUT" | grep -q "^DL_COEXIST_OK torch=.*cpu" \
  || fail "dl marker missing / not a CPU torch build: $DL_OUT"
printf '%s\n' "$DL_OUT" | grep -q "ort=1.29.0" \
  || fail "onnxruntime version not reported as 1.29.0"

/app/venv/bin/python - <<'PY' || fail "CUDA/toolkit clash checks failed"
import torch
assert torch.cuda.is_available() is False, "torch reports CUDA available (not CPU-only!)"
assert torch.__version__ == "2.5.1+cpu", "torch version not the pinned CPU build: %s" % torch.__version__
import numpy
print("numpy", numpy.__version__)
PY
NVIDIA=$(ls /app/venv/lib/python3.12/site-packages | grep -i nvidia || true)
[ -z "$NVIDIA" ] || fail "nvidia-* CUDA binding packages present: $NVIDIA"
NUMPY_COUNT=$(/app/venv/bin/pip list --disable-pip-version-check 2>/dev/null \
  | awk '$1=="numpy"{c++} END{print c+0}')
[ "$NUMPY_COUNT" -eq 1 ] || fail "expected a single numpy, found $NUMPY_COUNT"

log "dl: hidden spec cases"
/app/venv/bin/python3 /app/dl-coexist.py --spec /tests/hidden/dl/case2.json \
  >/tmp/dl2.out 2>/tmp/dl2.err \
  || fail "hidden dl case2 (valid tiny spec) failed: $(tail -1 /tmp/dl2.err)"
grep -q "^DL_COEXIST_OK" /tmp/dl2.out || fail "hidden dl case2 produced no DL_COEXIST_OK marker"
/app/venv/bin/python3 /app/dl-coexist.py --spec /tests/hidden/dl/case3.json \
  >/tmp/dl3.out 2>/tmp/dl3.err
DL3_RC=$?
[ "$DL3_RC" -ne 0 ] || fail "hidden dl case3 (malformed spec) must exit non-zero"
grep -q "^DL_COEXIST_OK" /tmp/dl3.out && fail "hidden dl case3 printed a marker on malformed spec"

# ===========================================================================
# 4. Local package-index server (C-ab35f97b): re-run + live client install
# ===========================================================================
log "server: reading hidden expectations"
read -r EXPECT_HOST EXPECT_PORT EXPECT_PROJ EXPECT_VER < <(
  python3 -c "import json;d=json.load(open('/tests/hidden/server/expect.json'));print(d['host'],d['port'],d['project'],d['version'])")

log "server: re-running serve-index.sh (restart)"
bash /app/serve-index.sh >/tmp/si.out 2>/tmp/si.err \
  || fail "serve-index.sh re-run failed: $(tail -1 /tmp/si.err)"
BASE="http://$EXPECT_HOST:$EXPECT_PORT"
OK_UP=""
for _ in $(seq 1 40); do
  if curl -sf "$BASE/" >/dev/null 2>&1; then OK_UP=1; break; fi
  sleep 0.25
done
[ -n "$OK_UP" ] || fail "index server not reachable on $BASE"

log "server: validating generated PEP-503 html"
grep -q "<a href=\"$EXPECT_PROJ/\">" /app/package-dir/index.html \
  || fail "package-dir/index.html has no link to $EXPECT_PROJ/"

python3 - <<'PY' || fail "swellkit/index.html anchors do not match real wheel files"
import json, os, re
expect = json.load(open("/tests/hidden/server/expect.json"))
proj = expect["project"]
pdir = "/app/package-dir"
sub = os.path.join(pdir, proj)
html = open(os.path.join(sub, "index.html")).read()
anchors = re.findall(r'href="([^"]+)"', html)
wheels = [a for a in anchors if a.endswith(".whl")]
real = sorted(f for f in os.listdir(sub) if f.endswith(".whl"))
assert wheels, "no wheel anchors in %s/index.html" % proj
assert sorted(wheels) == real, (sorted(wheels), real)
assert any("swellkit-%s-" % expect["version"] in w for w in wheels), wheels
print("swellkit/index.html ok:", wheels)
PY

( for f in $(python3 -c "import os,re;d='/app/package-dir/swellkit';print(' '.join(sorted(x for x in os.listdir(d) if x.endswith('.whl'))))" ); do
    code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/swellkit/$f"); [ "$code" = "200" ] || { echo "wheel $f -> $code"; exit 1; }
  done ) || fail "a staged wheel is not served over HTTP"
UNKNOWN=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/no-such-project/")
[ "$UNKNOWN" = "404" ] || fail "unknown project should 404, got $UNKNOWN"

log "server: fresh scratch-venv install from the live index"
rm -rf /tmp/cv
python3 -m venv /tmp/cv >/dev/null 2>&1 || fail "cannot create client venv"
/tmp/cv/bin/pip install -q --no-cache-dir --no-deps \
  --index-url "$BASE" --trusted-host "$EXPECT_HOST" \
  "$EXPECT_PROJ==$EXPECT_VER" >/tmp/cv_pip.log 2>&1 \
  || fail "client pip install failed: $(tail -3 /tmp/cv_pip.log)"
CV_VER=$(/tmp/cv/bin/python -c "import swellkit; print(swellkit.__version__)") \
  || fail "installed swellkit does not import in client venv"
[ "$CV_VER" == "$EXPECT_VER" ] || fail "client venv has swellkit $CV_VER != $EXPECT_VER"

grep -q "CLIENT_INSTALL_OK version=$EXPECT_VER" /app/client-install.log \
  || fail "client-install.log missing CLIENT_INSTALL_OK marker"

# ===========================================================================
# all good
# ===========================================================================
okay
