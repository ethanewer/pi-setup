#!/bin/bash
# Oracle solution for item-057-main: FRET overlap, protein cross-check, DNA
# codon design, provenance. Writes /app/result.json.
set -euo pipefail

cat > /app/solve.py <<'PYEOF'
#!/usr/bin/env python3
import json
import os
import numpy as np

BASE = "/app/data"

def read_spectrum(f):
    wl = []
    vals = []
    for line in open(os.path.join(BASE, f)):
        line = line.strip()
        if not line or line.startswith("wavelength"):
            continue
        a, b = line.split(",")
        wl.append(float(a)); vals.append(float(b))
    return np.array(vals, dtype=np.float64)

import os

# 1. FRET overlap
overlap = {}
for p in ["A", "B", "C"]:
    Em = read_spectrum(f"pair_{p}_donor_emission.csv")
    Ab = read_spectrum(f"pair_{p}_acceptor_absorption.csv")
    overlap[p] = float(np.sum((Em / Em.max()) * (Ab / Ab.max())) * 5.0)
best_pair = max(J, key=J.get)

# 2. protein cross-check
dh = json.load(open(os.path.join(BASE, "dhfr_protein.json")))
seq = dh["sequence"]
residue_count = len(seq)
g_fraction = seq.count("G") / residue_count
g_fraction_match = abs(g_fraction - dh["record_g_fraction"]) <= 0.005

# 3. DNA codon design
table = json.load(open(os.path.join(BASE, "codon_table_full.json")))["table"]
mapped = [c for c in seq if c in table]
dna = "".join(table[a][0] for a in mapped)
gc_fraction = (dna.count("G") + dna.count("C")) / len(dna)

# 4. provenance
srcs = json.load(open(os.path.join(BASE, "sources.json")))
used = [
    "pair_A_donor_emission.csv", "pair_A_acceptor_absorption.csv",
    "pair_B_donor_emission.csv", "pair_B_acceptor_absorption.csv",
    "pair_C_donor_emission.csv", "pair_C_acceptor_absorption.csv",
    "fluorophores.json", "dhfr_protein.json",
]
provenance_ok = all(f in srcs for f in used)

res = {
    "overlap": {k: float(round(v, 3)) for k, v in overlap.items()},
    "best_pair": best_pair,
    "residue_count": residue_count,
    "g_fraction": float(round(g_fraction, 4)),
    "g_fraction_match": bool(g_fraction_match),
    "dna": dna,
    "mapped_count": len(mapped),
    "dna_length": len(dna),
    "gc_fraction": float(round(gc_fraction, 3)),
    "provenance_ok": bool(provenance_ok),
}
json.dump(res, open("/app/result.json", "w"), indent=2)
print("written /app/result.json")
PYEOF

python3 /app/solve.py