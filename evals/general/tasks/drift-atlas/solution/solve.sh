#!/usr/bin/env bash
# Oracle for drift-atlas: author every deliverable by doing the real work.
#  * /app/channels.py  - ion-channel gating classes + rate constants
#  * /app/neuron.py    - multi-compartment HH cable simulator
#  * /app/spike-trace.json - somatic trace of the shipped morphology+stimulus
#  * /app/descriptors.py + /app/descriptors.json - rdkit descriptors
#  * /app/tuned-model.xml + /app/mujoco-load.txt - tuned MuJoCo model
#  * /app/warrior.red + /app/tournament.json - CoreWars tournament results
#  * /app/sizes.json  - measured sizes of every deliverable
set -euo pipefail
cd /app

# ---------------------------------------------------------------------------
# 1. Channels + neuron simulator
# ---------------------------------------------------------------------------
cat > /app/channels.py << 'PYEOF'
#!/usr/bin/env python3
"""channels.py -- ion-channel gating for the drift-atlas lab.

Exports the membrane gating rate functions used by neuron.py together with the
three channel classes that neuron.py binds against the loaded morphology.
Potentials in mV, time in ms, conductances in uS, capacitances in nF and
currents in nA.
"""
import math


def alpha_m(v):
    d = v + 40.0
    if abs(d) < 1e-7:
        return 1.0
    return 0.1 * d / (1.0 - math.exp(-d / 10.0))


def beta_m(v):
    return 4.0 * math.exp(-(v + 65.0) / 18.0)


def alpha_h(v):
    return 0.07 * math.exp(-(v + 65.0) / 20.0)


def beta_h(v):
    return 1.0 / (1.0 + math.exp(-(v + 35.0) / 10.0))


def alpha_n(v):
    d = v + 55.0
    if abs(d) < 1e-7:
        return 0.1
    return 0.01 * d / (1.0 - math.exp(-d / 10.0))


def beta_n(v):
    return 0.125 * math.exp(-(v + 65.0) / 80.0)


def steady_gates(v):
    """Steady-state (m, h, n) used as initial conditions."""
    tot = alpha_m(v) + beta_m(v)
    m0 = 0.0 if tot == 0.0 else alpha_m(v) / tot
    tot = alpha_h(v) + beta_h(v)
    h0 = 0.0 if tot == 0.0 else alpha_h(v) / tot
    tot = alpha_n(v) + beta_n(v)
    n0 = 0.0 if tot == 0.0 else alpha_n(v) / tot
    return m0, h0, n0


class Channel:
    name = "generic"
    rev = None
    gates = ()
    exp = {}

    def current(self, g, v, gates):
        factor = 1.0
        for gk, e in self.exp.items():
            factor *= gates[gk] ** e
        return g * factor * (v - self.rev)


class Sodium(Channel):
    name = "sodium"
    gates = ("m", "h")
    exp = {"m": 3, "h": 1}


class Potassium(Channel):
    name = "potassium"
    gates = ("n",)
    exp = {"n": 4}


class Leak(Channel):
    name = "leak"
    gates = ()
    exp = {}
PYEOF

cat > /app/neuron.py << 'PYEOF'
#!/usr/bin/env python3
"""neuron.py -- multi-compartment HH cable model for the drift-atlas lab.

Usage:
    python3 /app/neuron.py <morphology.json> <stimulus.json> <output.json>

The morphology JSON defines a tree of compartments (one is the soma).  The
stimulus JSON defines a constant somatic current pulse.  The simulation uses a
fixed-step explicit Euler scheme; every compartment carries Hodgkin-Huxley
sodium/potassium gating plus a passive leak, and adjacent compartments exchange
axial current through the series conductance `gS` (uS) toward their parent.

Output JSON: { "dt", "tmax", "v": [soma potential per step (mV)],
               "spikes": [soma spike times (ms)] }
"""
import json
import sys

import channels


def main(morph_path, stim_path, out_path):
    morph = json.load(open(morph_path))
    stim = json.load(open(stim_path))
    dt = float(morph["dt"])
    tmax = float(morph["tmax"])
    soma = morph["soma"]

    comps = {}
    for spec in morph["compartments"]:
        nm = spec["name"]
        comps[nm] = {
            "C": float(spec["C"]),
            "gna": float(spec["gNa"]),
            "gk": float(spec["gK"]),
            "gl": float(spec["gL"]),
            "ena": float(spec["Ena"]),
            "ek": float(spec["Ek"]),
            "eleak": float(spec["Eleak"]),
            "v0": float(spec.get("v0", -65.0)),
            "parent": spec.get("parent"),
            "gs": float(spec.get("gS", 0.0)),
            "nb": [],
        }
    for nm, c in comps.items():
        if c["parent"] and c["parent"] in comps:
            par = comps[c["parent"]]
            c["nb"].append((par, c["gs"]))
            par["nb"].append((c, c["gs"]))

    order = list(comps.keys())
    for nm in order:
        c = comps[nm]
        c["v"] = c["v0"]
        c["m"], c["h"], c["n"] = channels.steady_gates(c["v0"])

    steps = int(round(tmax / dt))
    vout = []
    spikes = []
    prev = -1e9
    t0 = float(stim["start"])
    dur = float(stim["duration"])
    amp = float(stim["amplitude"])

    for k in range(steps):
        t = k * dt
        istim = amp if (t0 <= t < t0 + dur) else 0.0
        # 1) gate update (explicit Euler)
        for nm in order:
            c = comps[nm]
            v = c["v"]
            c["m"] += dt * (channels.alpha_m(v) * (1 - c["m"])
                            - channels.beta_m(v) * c["m"])
            c["h"] += dt * (channels.alpha_h(v) * (1 - c["h"])
                            - channels.beta_h(v) * c["h"])
            c["n"] += dt * (channels.alpha_n(v) * (1 - c["n"])
                            - channels.beta_n(v) * c["n"])
        # 2) net membrane + cable current at the old potential
        for nm in order:
            c = comps[nm]
            v = c["v"]
            ion = (c["gna"] * c["m"] ** 3 * c["h"] * (v - c["ena"])
                   + c["gk"] * c["n"] ** 4 * (v - c["ek"])
                   + c["gl"] * (v - c["eleak"]))
            cable = 0.0
            for (nb, g) in c["nb"]:
                cable += g * (nb["v"] - v)
            cur = -ion + cable
            if nm == soma:
                cur += istim
            c["dV"] = cur / c["C"]
        # 3) integrate
        for nm in order:
            comps[nm]["v"] += dt * comps[nm]["dV"]
        av = comps[soma]["v"]
        vout.append(av)
        if prev <= 20.0 < av:
            spikes.append(round(t - dt / 2.0, 4))
        prev = av

    with open(out_path, "w") as fh:
        json.dump({"dt": dt, "tmax": tmax, "v": vout, "spikes": spikes}, fh,
                  separators=(",", ":"))
    print("neurons: steps", steps, "spikes", len(spikes))


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.stderr.write("usage: neuron.py <morph> <stim> <out>\n")
        sys.exit(2)
    main(sys.argv[1], sys.argv[2], sys.argv[3])
PYEOF

python3 /app/neuron.py /app/morphology.json /app/stimulus.json /app/spike-trace.json

# ---------------------------------------------------------------------------
# 2. rdkit descriptors
# ---------------------------------------------------------------------------
cat > /app/descriptors.py << 'PYEOF'
#!/usr/bin/env python3
"""descriptors.py -- ADMET-style molecular descriptors with exact types.

  python3 /app/descriptors.py --compute <smiles>   # prints one JSON line
  python3 /app/descriptors.py --write <smiles.txt> <out.json>

Valid molecules yield {"smiles", "logp" (float), "mw" (float), "hbd" (int),
"hba" (int), "rotb" (int), "tpsa" (float)}; invalid SMILES yield
{"smiles", "error": "invalid smiles"}.
"""
import json
import sys

from rdkit import Chem
from rdkit.Chem import Crippen, Descriptors, rdMolDescriptors


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


if __name__ == "__main__":
    if sys.argv[1] == "--compute" and len(sys.argv) == 3:
        print(json.dumps(compute(sys.argv[2])))
    elif sys.argv[1] == "--write" and len(sys.argv) == 4:
        smiles = [ln.strip() for ln in open(sys.argv[2]) if ln.strip() != ""]
        out = {"source": sys.argv[2], "molecules": [compute(s) for s in smiles]}
        json.dump(out, open(sys.argv[3], "w"), indent=2)
        print("wrote", sys.argv[3], "molecules", len(smiles))
    else:
        sys.exit("usage: descriptors.py --compute <smiles> | --write <txt> <out.json>")
PYEOF

python3 /app/descriptors.py --write /app/sample_smiles.txt /app/descriptors.json

# ---------------------------------------------------------------------------
# 3. MuJoCo tuning: raise the drive gain so the shoulder sweeps past 1.1 rad
# ---------------------------------------------------------------------------
python3 - << 'PYEOF'
import json
import mujoco

ref = open("/app/ref-model.xml").read()
tuned = ref.replace('gear="0.07"', 'gear="0.26"')
open("/app/tuned-model.xml", "w").write(tuned)

m = mujoco.MjModel.from_xml_path("/app/tuned-model.xml")
d = mujoco.MjData(m)
d.ctrl[0] = 2.0
mx = 0.0
for _ in range(1000):
    mujoco.mj_step(m, d)
    mx = max(mx, abs(d.qpos[0]))
if mx <= 1.1:
    raise SystemExit("tuning failed: tuned sweep %.3f rad" % mx)
open("/app/mujoco-load.txt", "w").write(
    "MUJOCO_OK tuned=%s freq=0 plugins=0 sweep=%.3f\n" % ("atlas-gain", mx))
print("mujoco: tuned model loads, steps, sweeps", round(mx, 3), "rad")
PYEOF

# ---------------------------------------------------------------------------
# 4. atlas-red warrior + tournament
# ---------------------------------------------------------------------------
cat > /app/warrior.red << 'PYEOF'
; Atlas-Red warrior for the drift-atlas arena: a division worm that floods the
; ring.  SPL doubles the fighter in place each cycle; the MOV 0,1 copy stamps
; a fresh worm cell one step ahead every pass, so the ring is quickly owned by
; warrior cells while the holdouts are buried in copies.
SPL 0
MOV 0 1
PYEOF

python3 - << 'PYEOF'
import json
import sys
sys.path.insert(0, "/app/corewar")
import core
res = core.tournament("/app/warrior.red", "/app/corewar/opponents")
json.dump(res, open("/app/tournament.json", "w"), indent=2)
if not res.get("all_wins"):
    raise SystemExit("tournament not won: %r" % res)
print("corewars: all rounds won", json.load(open("/app/tournament.json")))
PYEOF

# ---------------------------------------------------------------------------
# 5. sizes.json — measured byte sizes vs documented ceilings
# ---------------------------------------------------------------------------
python3 - << 'PYEOF'
import json
import os

LIMITS = [
    ("/app/neuron.py", 20000),
    ("/app/channels.py", 12000),
    ("/app/spike-trace.json", 700000),
    ("/app/descriptors.py", 20000),
    ("/app/descriptors.json", 20000),
    ("/app/ref-model.xml", 4000),
    ("/app/tuned-model.xml", 4000),
    ("/app/mujoco-load.txt", 4000),
    ("/app/warrior.red", 4000),
    ("/app/tournament.json", 20000),
    ("/app/sizes.json", 6000),
]
rows = []
for path, limit in LIMITS:
    if path == "/app/sizes.json":
        continue
    size = os.path.getsize(path)
    assert size <= limit, "%s exceeds %d" % (path, limit)
    rows.append({"path": path, "bytes": size, "limit": limit})
# sizes.json reports its own serialized length as its measured size.
base = list(rows)
x = 1000
for _loop in range(20):
    txt = json.dumps({"artifacts": base + [{"path": "/app/sizes.json", "bytes": x, "limit": 6000}]}, indent=2) + "\n"
    nx = len(txt)
    if nx == x:
        break
    x = nx
open("/app/sizes.json", "w").write(txt)
print("sizes.json:", json.dumps({"artifacts": base + [{"path": "/app/sizes.json", "bytes": x, "limit": 6000}]})[:200])
PYEOF

echo "solution complete"
exit 0