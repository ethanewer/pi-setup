#!/usr/bin/env bash
# Quartz Grove verifier. Runs as root after the agent finishes.
#
# Exercises every deliverable:
#   * runs /app/resolve.py on the primary + hidden specs (generalizes a resolver)
#   * installs /app/requirements.txt into a fresh venv and checks each pin holds
#   * confirms the edited primary spec has no disjoint module version pair
#   * checks the pre-existing GLOBAL numpy kept its exact version and that
#     /app/frozen_versions.json recorded that original value
#   * re-runs the reference example and byte-matches /app/example_check.log
#   * enforces a lean-footprint budget
set -uo pipefail

REWARD_FILE=/logs/verifier/reward.txt
RESOLVE=/app/resolve.py
REQ=/app/requirements.txt
mkdir -p "$(dirname "$REWARD_FILE")"

fail() { echo "VERIFY-FAIL: $*" >&2; echo 0 > "$REWARD_FILE"; exit 1; }
okay() { echo "REWARD-OK: $*" >&2; echo 1 > "$REWARD_FILE"; exit 0; }

# ---- deliverable presence ---------------------------------------------------
for f in /app/resolve.py /app/requirements.txt /app/environment.lock \
         /app/frozen_versions.json /app/example_check.log /app/venv \
         /app/example_check.py /app/spec.json; do
  [ -e "$f" ] || fail "missing deliverable/path: $f"
done
python3 -c "import ast; ast.parse(open('/app/resolve.py').read())" \
  || fail "/app/resolve.py has a syntax error"
# The documented invocation is `python3 /app/resolve.py`, so the executable
# bit is NOT part of the contract: a readable file run via `python3` passes.
[ -r "$RESOLVE" ] || fail "/app/resolve.py is not readable"

# ---- primary spec: no disjoint module pair may remain -----------------------
python3 - <<'PY' || fail "spec still contains an unresolvable module pair"
import json, re
TOK = re.compile(r"^(>=|<=|>|<|==)[0-9]+(?:\.[0-9]+)*$")
def virt(v): return tuple(int(p) for p in v.split("."))
def cmp_(a,b):
    x,y=virt(a),virt(b); return (x>y)-(x<y)
def toks(e):
    ts=[t.strip() for t in e.split(",") if t.strip()]
    out=[]
    for t in ts:
        m=TOK.match(t)
        if not m: raise ValueError(t)
        out.append((m.group(1), t[len(m.group(1)):]))
    return out
def sat(v,op,t):
    c=cmp_(v,t)
    return {">=":c>=0,"<=":c<=0,">":c>0,"<":c<0,"==":c==0}[op]
spec=json.load(open("/app/spec.json"))
cands=spec.get("candidates")
assert cands, "no candidates"
mods=spec.get("modules") or []
common=[c for c in cands
        if all(all(sat(c,op,t) for op,t in toks(m["numpy"])) for m in mods)]
assert common, "no candidate satisfies all modules (disjoint pair remains)"
print("primary spec is consistent")
PY

# ---- resolver on primary spec: lock + requirements must match expected ---
python3 "$RESOLVE" --spec /app/spec.json > /tmp/prim.out 2>/tmp/prim.err
PRIM_RC=$?
[ "$PRIM_RC" -eq 0 ] || fail "primary resolver resolved rc=$PRIM_RC: $(tail -1 /tmp/prim.err)"
python3 - <<'PY' || fail "primary lock does not match expected"
import json
lock=json.load(open("/tmp/prim.out"))
expect={"interface":"numpy","numpy":"1.26.4",
        "modules":{"frames":{"package":"pandas","version":"2.2.2"},
                   "solver":{"package":"scipy","version":"1.13.1"}},
        "consistent":True}
assert lock==expect, (lock, expect)
print("primary lock ok")
PY
cmp -s /app/environment.lock /tmp/prim.out \
  || fail "/app/environment.lock does not match the resolver's output"
python3 - <<'PY' || fail "requirements.txt does not match the expected pinned set"
import sys
pins={}
for ln in open("/app/requirements.txt"):
    ln=ln.strip()
    if not ln or ln.startswith("#"): continue
    if "==" not in ln: raise SystemExit("unpinned requirement: "+ln)
    n,v=ln.split("==",1); pins[n.strip()]=v.strip()
want={"numpy":"1.26.4","pandas":"2.2.2","scipy":"1.13.1"}
assert pins==want, (pins, want)
print("requirements.txt matches")
PY

# --- install from manifests into a FRESH venv; every pin must be honored ---
rm -rf /tmp/qv ${PVVENV:-} && python3 -m venv /tmp/qv >/dev/null
/tmp/qv/bin/pip install -q --no-cache-dir -r "$REQ" >/tmp/qv_pip.log 2>&1 \
  || fail "pip install -r failed: $(tail -2 /tmp/qv_pip.log)"
/tmp/qv/bin/python - <<'PY' || fail "installed versions do not honor pins"
import numpy, pandas, scipy
pins={}
for ln in open("/app/requirements.txt"):
    ln=ln.strip()
    if not ln or ln.startswith("#"): continue
    n,v=ln.split("==",1); pins[n.strip()]=v.strip()
got={"numpy":numpy.__version__,"pandas":pandas.__version__,"scipy":scipy.__version__}
for k,v in got.items():
    assert pins.get(k)==v, (k,pins.get(k),v)
print("pinned packages installed cleanly")
PY

# --- global numpy preserved --------------------------------------------------
ORIG="$(cat /app/.global_numpy_original)"
NOW="$(python3 -c 'import numpy; print(numpy.__version__)')"
[ "$NOW" = "$ORIG" ] || fail "global numpy was changed ($ORIG -> $NOW)"
python3 - "$ORIG" <<'PY' || fail "frozen_versions.json does not preserve the global version"
import json, sys
d=json.load(open("/app/frozen_versions.json"))
assert d["preserved"]["numpy"]==sys.argv[1], d
print("frozen_versions preserves global", sys.argv[1])
PY

# --- example rerun byte-matches the logged log, signature valid -------------
[ -x /app/venv/bin/python ] || fail "venv python missing"
/app/venv/bin/python /app/example_check.py > /tmp/ec_now.log 2>/tmp/ec_err.log \
  || fail "example failed under venv: $(tail -2 /tmp/ec_err.log)"
cmp -s /tmp/ec_now.log /app/example_check.log \
  || fail "example_check.log does not match a fresh run"
/app/venv/bin/python - <<'PY' || fail "example marker/signature is wrong"
import hashlib, os
sess=os.environ.get("QUARTZ_GROVE_SESSION","")
pins={}
for line in open("/app/requirements.txt"):
    line=line.strip()
    if line and not line.startswith("#") and "==" in line:
        n,v=line.split("==",1); pins[n.strip()]=v.strip()
joined="|".join([sess,pins["numpy"],pins["pandas"],pins["scipy"]])
sig=hashlib.sha256(joined.encode()).hexdigest()[:16]
line=open("/app/example_check.log").read().strip()
assert line==f"QUARTZ_GROVE_OK sig={sig}", line
print("example marker verified")
PY

# --- footprint budget + leanness ---------------------------------------------
DU=$(du -sb /app | awk '{print $1}')
[ "$DU" -lt 1100000000 ] || fail "footprint too large: ${DU}B"
python3 - <<'PY' || fail "bloated extra framework present"
import os
BIG={"torch","tensorflow","transformers","mxnet","keras","jax"}
for base,dirs,_ in os.walk("/app/venv/lib"):
    if os.path.basename(base)=="site-packages":
        hits=BIG & set(dirs)
        if hits: raise SystemExit(sorted(hits))
print("lean venv")
PY

# ---  hidden cases: resolver generalization ----------------------------------
[ -d /tests/hidden ] || fail "/tests/hidden missing"
count=0
for cdir in /tests/hidden/*; do
  [ -d "$cdir" ] || continue
  [ -f "$cdir/spec.json" ] || fail "hidden $cdir missing spec.json"
  [ -f "$cdir/expected.json" ] || fail "hidden $cdir missing expected.json"
  python3 "$RESOLVE" --spec "$cdir/spec.json" > "/tmp/h_${count}.out" 2>"/tmp/h_${count}.err"
  HRC=$?
  python3 - "/tmp/h_${count}.out" "$cdir/expected.json" "$HRC" <<'PY'
import json, sys
outf=sys.argv[1]; expf=sys.argv[2]; rc=int(sys.argv[3])
raw=open(outf).read().strip()
got=json.loads(raw) if raw else None
exp=json.load(open(expf))
assert rc==exp.get("exit",0), (rc, exp)
if exp.get("exit",0)==0:
    assert got is not None and got==exp["lock"], (got, exp.get("lock"))
else:
    assert got is None, "unexpected JSON on error path"
PY
  hrc=$?
  [ "$hrc" -eq 0 ] || fail "hidden case $cdir failed"
  count=$((count+1))
done
[ "$count" -ge 2 ] || fail "expected >=2 hidden cases, got $count"

okay "primary + $count hidden cases passed"