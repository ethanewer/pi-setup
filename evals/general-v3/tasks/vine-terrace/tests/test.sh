#!/usr/bin/env bash
# Vine Terrace verifier (executes-deliverable).
#   /app        = agent work (analyze.py, primers.tsv, adjust.json)
#   /tests      = read-only (hidden inputs + reference outputs)
# Checks every deliverable on visible + hidden inputs across the five sliced
# competencies, then writes a numeric reward to /logs/verifier/reward.txt.
set -uo pipefail
mkdir -p /logs/verifier

# ---- 0. deliverables exist ----------------------------------------------- #
FAIL=""
for f in /app/analyze.py /app/primers.tsv /app/adjust.json; do
    [ -f "$f" ] || FAIL="${FAIL}missing deliverable $f\n"
done

if [ -n "$FAIL" ]; then
    printf "$FAIL" >&2
    echo "0" > /logs/verifier/reward.txt
    echo "final-reward=0"
    exit 0
fi

# ---- 1. authoritative check ---------------------------------------------- #
OUT=$(python3 - <<'PY'
import importlib.util, json
import numpy as np

fails = []
def load_analyze(path):
    spec = importlib.util.spec_from_file_location("ag_analyze", path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m
def chk(name, ok, detail=""):
    if not ok:
        fails.append(f"{name}: {detail}")

try:
    A = load_analyze("/app/analyze.py")
except Exception as e:
    print("IMPORT-FAIL", repr(e)); print("REWARD=0"); raise SystemExit(0)

# visible deliverables
try:
    exp_tsv = open("/tests/expected/primersV.tsv").read().rstrip("\n")
    got_tsv = open("/app/primers.tsv").read().rstrip("\n")
    chk("primers.tsv", got_tsv == exp_tsv, "deliverable tsv mismatch")
except Exception as e:
    chk("primers.tsv", False, repr(e))
try:
    exp_adj = json.load(open("/tests/expected/adjustV.json"))
    got_adj = json.load(open("/app/adjust.json"))
    chk("adjust.json", got_adj == exp_adj, f"{got_adj} != {exp_adj}")
except Exception as e:
    chk("adjust.json", False, repr(e))

# A. hist (hidden + visible)
try:
    pts = np.load("/tests/hidden/hist/pointsB.npy"); box=json.load(open("/tests/hidden/hist/box.json"))
    exp = np.load("/tests/hidden/hist/expected.npy")
    g = A.points_to_histogram(pts, box["box"], tuple(box["bins"]))
    chk("hist hidden", g.shape==exp.shape and np.allclose(g, exp, atol=1e-9),
        f"shape {g.shape}/{exp.shape} maxdiff {np.max(np.abs(g-exp)) if g.shape==exp.shape else 'NA'}")
    if g.shape==exp.shape and g.size:
        chk("hist sum1", abs(float(g.sum())-1.0) < 1e-9, f"sum {g.sum()}")
except Exception as e:
    chk("hist hidden", False, repr(e))
try:
    ptsV=np.load("/app/data/clusters.npy"); boxV=json.load(open("/app/data/clusters_box.json"))
    expV=np.load("/tests/expected/histV.npy")
    gV=A.points_to_histogram(ptsV, boxV["box"], tuple(boxV["bins"]))
    chk("hist visible", gV.shape==expV.shape and np.allclose(gV, expV, atol=1e-9),
        f"maxdiff {np.max(np.abs(gV-expV)) if gV.shape==expV.shape else 'NA'}")
except Exception as e:
    chk("hist visible", False, repr(e))

# B. spectrum (hidden + visible)
try:
    x,y=A.parse_spectrum("/tests/hidden/spectrum/run882.spect")
    ex=np.load("/tests/hidden/spectrum/expected_x.npy"); ey=np.load("/tests/hidden/spectrum/expected_y.npy")
    chk("spectrum hidden", x.shape==ex.shape and np.allclose(x,ex,atol=1e-9)
        and y.shape==ey.shape and np.allclose(y,ey,atol=1e-9), "x/y mismatch")
except Exception as e:
    chk("spectrum hidden", False, repr(e))
try:
    x,y=A.parse_spectrum("/app/spectrum/run471.spect")
    ex=np.load("/tests/expected/x471.npy"); ey=np.load("/tests/expected/y471.npy")
    chk("spectrum visible", x.shape==ex.shape and np.allclose(x,ex,atol=1e-9)
        and y.shape==ey.shape and np.allclose(y,ey,atol=1e-9), "x/y mismatch")
except Exception as e:
    chk("spectrum visible", False, repr(e))

# C. causal adjustment sets (hidden + visible)
try:
    s=A.minimal_adjustment_sets("/tests/hidden/causal/graphB.txt")
    es=json.load(open("/tests/hidden/causal/expected.json"))
    chk("causal hidden", s==es, f"{s} != {es}")
except Exception as e:
    chk("causal hidden", False, repr(e))
try:
    s=A.minimal_adjustment_sets("/app/causal/graphA.txt")
    es=json.load(open("/tests/expected/adjustV.json"))
    chk("causal visible", s==es, f"{s} != {es}")
except Exception as e:
    chk("causal visible", False, repr(e))

# D. primers (hidden parts + bounds)
try:
    pr=A.design_primers("/tests/hidden/primer/partsB.tsv")
    norm=[{"name":p["name"],"seq":p["seq"],"anneal_len":p["anneal_len"],
           "tm":round(float(p["tm"]),1),"site":p["site"],"junction":p["junction"]} for p in pr]
    epr=json.load(open("/tests/hidden/primer/expected.json"))
    chk("primers hidden", norm==epr, f"count/seq/site/tm mismatch: {norm} != {epr}")
    if all(18 <= p["anneal_len"] <= 24 for p in norm):
        pass
    else:
        chk("primers bounds", False, "annealing length out of [18,24]")
except Exception as e:
    chk("primers hidden", False, repr(e))

# E. biophysics -> jaxley (hidden morphology/params)
try:
    V=A.membrane_response("/tests/hidden/biophys/morph.swc","/tests/hidden/biophys/params.json")
    eV=np.load("/tests/hidden/biophys/expected_v.npy")
    chk("biophys shape", V.shape==eV.shape, f"{V.shape} != {eV.shape}")
    if V.shape==eV.shape:
        md=float(np.max(np.abs(V-eV))) if V.size else 0.0
        chk("biophys trace", np.allclose(V,eV,rtol=1e-4,atol=1e-2), f"max abs diff {md}")
except Exception as e:
    chk("biophys", False, repr(e))

if fails:
    print(" ; ".join(fails))
    print("REWARD=0")
else:
    print("ALL-CASES-PASS")
    print("REWARD=1")
PY
)

echo "$OUT"
if [ -n "$FAIL" ]; then
    echo "0" > /logs/verifier/reward.txt
    echo "final-reward=0"
else
    if echo "$OUT" | grep -q "REWARD=1"; then
        echo "1" > /logs/verifier/reward.txt
        echo "final-reward=1"
    else
        echo "0" > /logs/verifier/reward.txt
        echo "final-reward=0"
    fi
fi
