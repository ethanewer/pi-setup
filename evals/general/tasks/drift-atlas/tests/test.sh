#!/usr/bin/env bash
# drift-atlas verifier --- runs as root after the agent finished.
#
# Executes every deliverable at literal /app paths:
#   * /app/neuron.py  (+ /app/channels.py)  on the shipped morphology AND on
#     every hidden morphology/stimulus, against an independent reference
#     implementation of the documented explicit-Euler cable model; /app/spike-
#     trace.json must equal the reference result for the shipped inputs.
#   * /app/descriptors.py on the shipped sample molecules AND every hidden
#     SMILES, against an independent rdkit recomputation (values AND Python
#     types); /app/descriptors.json must equal the reference for the sample.
#   * /app/tuned-model.xml must load and step under clean plugin-free MuJoCo
#     with the shoulder sweeping past 1.1 rad in 2 s (ctrl=2.0) while the
#     pristine /app/ref-model.xml stays below it and stays byte-identical to
#     /opt/pristine/ref-model.xml; /app/mujoco-load.txt must carry MUJOCO_OK.
#   * /app/warrior.red must win the deterministic Atlas-Red tournament against
#     every shipped holdout (pristine engine); /app/tournament.json must agree.
#   * /app/sizes.json must list every deliverable with measured bytes equal to
#     its real size and within its documented ceiling.
set -euo pipefail
trap '[ -f /logs/verifier/reward.txt ] || echo 0 > /logs/verifier/reward.txt' EXIT

REWARD=/logs/verifier/reward.txt
mkdir -p "$(dirname "$REWARD")"
fail() { echo "VERIFY-FAIL: $*" >&2; echo 0 > "$REWARD"; exit 1; }
ok()   { echo "REWARD-OK: $*" >&2; echo 1 > "$REWARD"; exit 0; }

# ===========================================================================
# 0. deliverable presence / syntax
# ===========================================================================
for f in /app/neuron.py /app/channels.py /app/spike-trace.json \
         /app/descriptors.py /app/descriptors.json /app/ref-model.xml \
         /app/tuned-model.xml /app/mujoco-load.txt /app/warrior.red \
         /app/tournament.json /app/sizes.json; do
  [ -f "$f" ] || fail "deliverable missing: $f"
  [ -s "$f" ] || fail "deliverable empty: $f"
done
python3 -c "import ast; ast.parse(open('/app/neuron.py').read())" || fail "neuron.py syntax"
python3 -c "import ast; ast.parse(open('/app/channels.py').read())" || fail "channels.py syntax"
python3 -c "import ast; ast.parse(open('/app/descriptors.py').read())" || fail "descriptors.py syntax"
python3 -c "import json; json.load(open('/app/sizes.json'))" || fail "sizes.json invalid"

# ===========================================================================
# 1. neuron + channels
# ===========================================================================
cat > /tmp/ref_neuron.py << 'PYEOF'
#!/usr/bin/env python3
"""Independent reference for drift-atlas neuron.py.

Implements the documented multi-compartment HH cable model with an explicit
Euler scheme identical in behavior to the contract in instruction.md, without
importing or reading /app/neuron.py or /app/channels.py.
"""
import json
import math
import sys


def am(v):
    d = v + 40.0
    return (0.1 * d / (1.0 - math.exp(-d / 10.0))) if abs(d) > 1e-7 else 1.0


def bm(v):
    return 4.0 * math.exp(-(v + 65.0) / 18.0)


def ah(v):
    return 0.07 * math.exp(-(v + 65.0) / 20.0)


def bh(v):
    return 1.0 / (1.0 + math.exp(-(v + 35.0) / 10.0))


def an(v):
    d = v + 55.0
    return (0.01 * d / (1.0 - math.exp(-d / 10.0))) if abs(d) > 1e-7 else 0.1


def bn(v):
    return 0.125 * math.exp(-(v + 65.0) / 80.0)


def gates0(v):
    return (am(v) / (am(v) + bm(v)), ah(v) / (ah(v) + bh(v)),
            an(v) / (an(v) + bn(v)))


def main(morph, stim, out):
    dt = float(morph["dt"]); tmax = float(morph["tmax"]); soma = morph["soma"]
    comps = {}
    for spec in morph["compartments"]:
        nm = spec["name"]
        comps[nm] = {"C": float(spec["C"]), "gna": float(spec["gNa"]),
                     "gk": float(spec["gK"]), "gl": float(spec["gL"]),
                     "ena": float(spec["Ena"]), "ek": float(spec["Ek"]),
                     "eleak": float(spec["Eleak"]),
                     "v0": float(spec.get("v0", -65.0)),
                     "parent": spec.get("parent"),
                     "gs": float(spec.get("gS", 0.0)), "nb": []}
    for nm, c in comps.items():
        if c["parent"] and c["parent"] in comps:
            p = comps[c["parent"]]
            c["nb"].append((p, c["gs"])); p["nb"].append((c, c["gs"]))
    order = list(comps.keys())
    for nm in order:
        c = comps[nm]
        c["v"] = c["v0"]
        c["m"], c["h"], c["n"] = gates0(c["v0"])
    steps = int(round(tmax / dt))
    t0 = float(stim["start"]); dur = float(stim["duration"]); amp = float(stim["amplitude"])
    V = []; spikes = []; prev = -1e9
    for k in range(steps):
        t = k * dt
        istim = amp if (t0 <= t < t0 + dur) else 0.0
        for nm in order:
            c = comps[nm]; v = c["v"]
            c["m"] += dt * (am(v) * (1 - c["m"]) - bm(v) * c["m"])
            c["h"] += dt * (ah(v) * (1 - c["h"]) - bh(v) * c["h"])
            c["n"] += dt * (an(v) * (1 - c["n"]) - bn(v) * c["n"])
        for nm in order:
            c = comps[nm]; v = c["v"]
            ion = (c["gna"] * c["m"] ** 3 * c["h"] * (v - c["ena"])
                   + c["gk"] * c["n"] ** 4 * (v - c["ek"])
                   + c["gl"] * (v - c["eleak"]))
            cab = 0.0
            for (nb, g) in c["nb"]:
                cab += g * (nb["v"] - v)
            cur = -ion + cab
            if nm == soma:
                cur += istim
            c["dV"] = cur / c["C"]
        for nm in order:
            comps[nm]["v"] += dt * comps[nm]["dV"]
        vv = comps[soma]["v"]; V.append(vv)
        if prev <= 20.0 < vv:
            spikes.append(round(t - dt / 2.0, 4))
        prev = vv
    json.dump({"dt": dt, "tmax": tmax, "v": V, "spikes": spikes},
              open(out, "w"), separators=(",", ":"))


if __name__ == "__main__":
    main(json.load(open(sys.argv[1])), json.load(open(sys.argv[2])), sys.argv[3])
PYEOF

python3 /tmp/ref_neuron.py /app/morphology.json /app/stimulus.json /tmp/ref_default.json
python3 /app/neuron.py /app/morphology.json /app/stimulus.json /tmp/out_default.json \
  > /tmp/neuron_default.log 2>&1 || fail "neuron.py failed on shipped inputs"
python3 - << 'PYEOF'
import json, sys

def cmp_trace(a, b):
    if abs(a["dt"] - b["dt"]) > 1e-9 or abs(a["tmax"] - b["tmax"]) > 1e-9:
        return "dt/tmax mismatch"
    if len(a["v"]) != len(b["v"]):
        return "v length %d vs %d" % (len(a["v"]), len(b["v"]))
    mx = max((abs(x - y) for x, y in zip(a["v"], b["v"])), default=0.0)
    scale = max((abs(x) for x in a["v"]), default=1.0)
    if mx > 0.05 and mx / max(scale, 1e-9) > 0.02:
        return "v diverged: max abs diff %.4f" % mx
    if len(a["spikes"]) != len(b["spikes"]):
        return "spike count %d vs %d" % (len(a["spikes"]), len(b["spikes"]))
    for x, y in zip(a["spikes"], b["spikes"]):
        if abs(x - y) > 0.15:
            return "spike time %.4f vs %.4f" % (x, y)
    return None

d1 = json.load(open("/app/spike-trace.json"))
d2 = json.load(open("/tmp/ref_default.json"))
err = cmp_trace(d1, d2)
if err:
    print("FAIL trace: " + err); sys.exit(1)
d3 = json.load(open("/tmp/out_default.json"))
err = cmp_trace(d3, d2)
if err:
    print("FAIL re-run trace: " + err); sys.exit(1)
print("neuron default trace OK (%d spikes)" % len(d2["spikes"]))
PYEOF
python3 - << 'PYEOF'
# channels.py must carry the reference gating constants and channel classes.
import math, sys
sys.path.insert(0, "/app")
import channels

def am(v):
    d = v + 40.0
    return (0.1 * d / (1.0 - math.exp(-d / 10.0))) if abs(d) > 1e-7 else 1.0
def bm(v): return 4.0 * math.exp(-(v + 65.0) / 18.0)
def ah(v): return 0.07 * math.exp(-(v + 65.0) / 20.0)
def bh(v): return 1.0 / (1.0 + math.exp(-(v + 35.0) / 10.0))
def an(v):
    d = v + 55.0
    return (0.01 * d / (1.0 - math.exp(-d / 10.0))) if abs(d) > 1e-7 else 0.1
def bn(v): return 0.125 * math.exp(-(v + 65.0) / 80.0)

probe = [-65.0, -40.0, -20.0, 0.0, 20.0, 40.0]
for v in probe:
    for name, ref in (("alpha_m", am), ("beta_m", bm), ("alpha_h", ah),
                      ("beta_h", bh), ("alpha_n", an), ("beta_n", bn)):
        got = getattr(channels, name)(v)
        if abs(got - ref(v)) > 1e-9:
            print("FAIL %s(%s)=%r want %r" % (name, v, got, ref(v)))
            sys.exit(1)
for cls in (channels.Sodium, channels.Potassium, channels.Leak):
    if not hasattr(cls, "exp") or not hasattr(cls, "rev"):
        print("FAIL channel class %s lacks exp/rev" % cls.__name__); sys.exit(1)
if channels.Sodium.exp != {"m": 3, "h": 1}:
    print("FAIL sodium exponents"); sys.exit(1)
if channels.Potassium.exp != {"n": 4}:
    print("FAIL potassium exponents"); sys.exit(1)
print("channels constants OK")
PYEOF

# hidden neuron cases
[ -d /tests/hidden ] || fail "/tests/hidden missing"
hcount=0
for cdir in /tests/hidden/*; do
  [ -d "$cdir" ] || continue
  [ -f "$cdir/morphology.json" ] && [ -f "$cdir/stimulus.json" ] || fail "hidden case $cdir incomplete"
  python3 /app/neuron.py "$cdir/morphology.json" "$cdir/stimulus.json" /tmp/hout_$hcount.json \
    >/tmp/hlog_$hcount.txt 2>&1 || fail "neuron.py failed on $cdir"
  python3 /tmp/ref_neuron.py "$cdir/morphology.json" "$cdir/stimulus.json" /tmp/href_$hcount.json \
    || fail "reference failed on $cdir"
  python3 - "$hcount" << 'PYEOF' || fail "hidden neuron $1 mismatch"
import json, sys
h = sys.argv[1]
a = json.load(open("/tmp/hout_%s.json" % h))
b = json.load(open("/tmp/href_%s.json" % h))
if abs(a["dt"] - b["dt"]) > 1e-9 or abs(a["tmax"] - b["tmax"]) > 1e-9:
    sys.exit("dt/tmax mismatch")
if len(a["v"]) != len(b["v"]):
    sys.exit("v length")
mx = max((abs(x - y) for x, y in zip(a["v"], b["v"])), default=0.0)
scale = max((abs(x) for x in b["v"]), default=1.0)
if mx > 0.05 and mx / scale > 0.02:
    sys.exit("v diverged %.4f" % mx)
if a["spikes"] != b["spikes"]:
    sys.exit("spikes %s vs %s" % (a["spikes"], b["spikes"]))
print("hidden neuron %s OK (%d spikes)" % (h, len(b["spikes"])))
PYEOF
  hcount=$((hcount + 1))
done
[ "$hcount" -ge 2 ] || fail "need >=2 hidden cases, got $hcount"

# ===========================================================================
# 2. descriptors
# ===========================================================================
cat > /tmp/ref_desc.py << 'PYEOF'
#!/usr/bin/env python3
"""Independent rdkit recomputation for the drift-atlas descriptor checks."""
import json
import sys
from rdkit import Chem
from rdkit.Chem import Crippen, rdMolDescriptors


def compute(smiles):
    mol = Chem.MolFromSmiles(smiles)
    if mol is None:
        return {"smiles": smiles, "error": "invalid smiles"}
    return {
        "smiles": smiles,
        "logp": float(Crippen.MolLogP(mol)),
        "mw": float(rdMolDescriptors.CalcExactMolWt(mol)),
        "hbd": int(rdMolDescriptors.CalcNumHBD(mol)),
        "hba": int(rdMolDescriptors.CalcNumHBA(mol)),
        "rotb": int(rdMolDescriptors.CalcNumRotatableBonds(mol)),
        "tpsa": float(rdMolDescriptors.CalcTPSA(mol)),
    }


def check(agent, ref):
    if "error" in ref:
        return "error" in agent
    if "error" in agent:
        return False
    for k in ref:
        if k not in agent:
            return False
        if isinstance(ref[k], str):
            if agent[k] != ref[k]:
                return False
        elif isinstance(ref[k], bool):
            if agent[k] != ref[k]:
                return False
        elif isinstance(ref[k], int):
            if not isinstance(agent[k], int) or agent[k] != ref[k]:
                return False
        else:
            if not isinstance(agent[k], float):
                return False
            if abs(agent[k] - ref[k]) > 1e-6:
                return False
    return True


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "sample":
        smis = [ln.strip() for ln in open("/app/sample_smiles.txt")
                if ln.strip() != ""]
        print(json.dumps([compute(s) for s in smis]))
        sys.exit(0)
PYEOF

# default deliverable descriptors.json
python3 - << 'PYEOF'
import json, sys
sys.path.insert(0, "/tmp")
import ref_desc
ref = ref_desc.compute
smis = [ln.strip() for ln in open("/app/sample_smiles.txt") if ln.strip() != ""]
want = [ref(s) for s in smis]
try:
    d = json.load(open("/app/descriptors.json"))
except Exception as e:
    print("FAIL descriptors.json unreadable: %r" % e); sys.exit(1)
mol = d.get("molecules")
if not isinstance(mol, list) or len(mol) != len(want):
    print("FAIL descriptors.json molecules"); sys.exit(1)
for i, (a, r) in enumerate(zip(mol, want)):
    ok = ref_desc.check(dict(a), dict(r))
    if not ok:
        print("FAIL descriptors.json mol %d %r" % (i, a.get("smiles"))); sys.exit(1)
print("descriptors.json OK (%d molecules)" % len(want))
PYEOF

# hidden descriptor sets
cat > /tmp/check_desc.py << 'PYEOF'
#!/usr/bin/env python3
import json
import subprocess
import sys
sys.path.insert(0, "/tmp")
import ref_desc
smi = sys.argv[1]
ref = ref_desc.compute(smi)
raw = subprocess.check_output(
    ["python3", "/app/descriptors.py", "--compute", smi]).decode()
agent = json.loads(raw)
if not ref_desc.check(agent, ref):
    sys.exit(1)
PYEOF
dcount=0
for cdir in /tests/hidden/*; do
  [ -d "$cdir" ] || continue
  [ -f "$cdir/smiles.txt" ] || fail "hidden case $cdir missing smiles.txt"
  while IFS= read -r line; do
    smi=${line%"${line##*[![:space:]]}"}   # trim trailing
    smi=${smi#"${smi%%[![:space:]]*}"}     # trim leading
    python3 /tmp/check_desc.py "$smi" || fail "descriptors mismatch on $(basename $cdir): $smi"
  done < "$cdir/smiles.txt"
  dcount=$((dcount + 1))
done
[ "$dcount" -ge 2 ] || fail "need >=2 hidden descriptor sets"

# ===========================================================================
# 3. mujoco
# ===========================================================================
cmp -s /app/ref-model.xml /opt/pristine/ref-model.xml \
  || fail "ref-model.xml modified (must stay byte-identical)"
cmp -s /app/tuned-model.xml /app/ref-model.xml \
  && fail "tuned-model.xml identical to reference (no tuning happened)"
grep -q "^MUJOCO_OK" /app/mujoco-load.txt || fail "mujoco-load.txt lacks MUJOCO_OK"
python3 - << 'PYEOF'
import sys
import mujoco

def sweep(path, ctrl, seconds=2.0):
    m = mujoco.MjModel.from_xml_path(path)
    d = mujoco.MjData(m)
    mujoco.mj_resetData(m, d)
    d.ctrl[0] = ctrl
    n = int(round(seconds / m.opt.timestep))
    mx = 0.0
    for _ in range(n):
        mujoco.mj_step(m, d)
        mx = max(mx, abs(d.qpos[0]))
    return mx

tuned = sweep("/app/tuned-model.xml", 2.0)
ref = sweep("/opt/pristine/ref-model.xml", 2.0)
if tuned <= 1.1:
    print("FAIL tuned sweep %.3f rad (need > 1.1)" % tuned); sys.exit(1)
if ref > 1.1:
    print("FAIL reference drifts %.3f rad (must stay < 1.1)" % ref); sys.exit(1)
print("mujoco OK: tuned %.3f rad, ref %.3f rad" % (tuned, ref))
PYEOF

# ===========================================================================
# 4. atlas-red tournament
# ===========================================================================
for f in core.py opponents/guardian.red opponents/stalker.red opponents/wraith.red; do
  cmp -s "/app/corewar/$f" "/opt/pristine/corewar/$f" \
    || fail "engine/opponent tampered: /app/corewar/$f"
done
[ -s /app/warrior.red ] || fail "warrior.red too small"
python3 - << 'PYEOF'
import json, sys
sys.path.insert(0, "/opt/pristine/corewar")
import core
res = core.tournament("/app/warrior.red", "/app/corewar/opponents")
if not res.get("all_wins"):
    print("FAIL tournament lost: %r" % res); sys.exit(1)
d = json.load(open("/app/tournament.json"))
if d.get("all_wins") is not True:
    print("FAIL tournament.json all_wins not true"); sys.exit(1)
by = {r["opponent"]: r["warrior_wins"] for r in d.get("rounds", [])}
for opp in sorted(res["rounds"], key=lambda r: r["opponent"]):
    if not opp["warrior_wins"]:
        print("FAIL recompute: %s" % opp); sys.exit(1)
    if by.get(opp["opponent"]) is not True:
        print("FAIL tournament.json disagrees on %s" % opp["opponent"]); sys.exit(1)
print("corewars OK: all rounds won vs %s" % ", ".join(sorted(by)))
PYEOF

# ===========================================================================
# 5. sizes.json
# ===========================================================================
python3 - << 'PYEOF'
import json, os, sys
d = json.load(open("/app/sizes.json"))
rows = d.get("artifacts")
if not isinstance(rows, list):
    print("FAIL sizes.json artifacts"); sys.exit(1)
need = {"/app/neuron.py", "/app/channels.py", "/app/spike-trace.json",
        "/app/descriptors.py", "/app/descriptors.json", "/app/ref-model.xml",
        "/app/tuned-model.xml", "/app/mujoco-load.txt", "/app/warrior.red",
        "/app/tournament.json", "/app/sizes.json"}
seen = set()
for r in rows:
    p = r.get("path")
    if p not in need:
        print("FAIL sizes.json unexpected path %s" % p); sys.exit(1)
    real = os.path.getsize(p)
    if int(r.get("bytes")) != real:
        print("FAIL %s reported %d real %d" % (p, r.get("bytes"), real)); sys.exit(1)
    if real > int(r.get("limit")):
        print("FAIL %s size %d over limit %d" % (p, real, r.get("limit"))); sys.exit(1)
    seen.add(p)
if seen != need:
    print("FAIL sizes.json missing rows: %s" % (need - seen)); sys.exit(1)
print("sizes.json OK (%d artifacts within limits)" % len(rows))
PYEOF

ok "all subsystems verified"