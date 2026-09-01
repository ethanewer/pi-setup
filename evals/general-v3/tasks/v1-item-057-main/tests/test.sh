#!/bin/bash
# Verifier for item-057-main.
mkdir -p /logs/verifier
reward=0

if [ -f /app/result.json ]; then
  if python3 - <<'PY'
import json, os
import numpy as np

BASE = "/app/data"

def read_spectrum(f):
    wl = []; vals = []
    for line in open(os.path.join(BASE, f)):
        line = line.strip()
        if not line or line.startswith("wavelength"):
            continue
        a, b = line.split(",")
        wl.append(float(a)); vals.append(float(b))
    return np.array(vals, dtype=np.float64)

overlap = {}
for p in ["A", "B", "C"]:
    Em = read_spectrum(f"pair_{p}_donor_emission.csv")
    Ab = read_spectrum(f"pair_{p}_acceptor_absorption.csv")
    overlap[p] = float(np.sum((Em / Em.max()) * (Ab / Ab.max())) * 5.0)
best = max(overlap, key=overlap.get)

dh = json.load(open(os.path.join(BASE, "dhfr_protein.json")))
seq = dh["sequence"]
residue_count = len(seq)
g_fraction = seq.count("G") / residue_count
g_match = abs(g_fraction - dh["record_g_fraction"]) <= 0.005

table = json.load(open(os.path.join(BASE, "codon_table_full.json")))["table"]
mapped_seq = [c for c in seq if c in table]
rev = {}
for aa, codons in table.items():
    for c in codons:
        rev[c] = aa

srcs = json.load(open(os.path.join(BASE, "sources.json")))
used = [
    "pair_A_donor_emission.csv", "pair_A_acceptor_absorption.csv",
    "pair_B_donor_emission.csv", "pair_B_acceptor_absorption.csv",
    "pair_C_donor_emission.csv", "pair_C_acceptor_absorption.csv",
    "fluorophores.json", "dhfr_protein.json",
]
prov_ok = all(f in srcs for f in used)

res = json.load(open("/app/result.json"))

for p in "ABC":
    assert abs(res["overlap"][p] - overlap[p]) <= 1e-3, (p, res["overlap"][p], overlap[p])
assert res["best_pair"] == best, (res["best_pair"], best)
assert res["residue_count"] == residue_count
assert abs(res["g_fraction"] - g_fraction) <= 1e-4
assert bool(res["g_fraction_match"]) == bool(g_match)

dna = res["dna"]
assert res["mapped_count"] == len(mapped_seq)
assert res["dna_length"] == len(dna) == 3 * len(mapped_seq)
decoded = [rev.get(dna[i:i+3], "?") for i in range(0, len(dna), 3)]
assert decoded == mapped_seq, "DNA does not decode to the protein"
gfract = (dna.count("G") + dna.count("C")) / len(dna)
assert abs(res["gc_fraction"] - gfract) <= 0.02
assert 0.15 <= gfract <= 0.85
assert bool(res["provenance_ok"]) == prov_ok
PY
  then
    reward=1
  fi
fi

echo "$reward" > /logs/verifier/reward.txt