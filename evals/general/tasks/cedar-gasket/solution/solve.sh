#!/bin/bash
# Oracle for cedar-gasket. Writes the two source-module deliverables under /app
# (pooling.py, featurizer.py) and RUNS the solver to produce embeddings.npy and
# smiles.npz. Never reads /tests.
set -euo pipefail

cat > /app/pooling.py <<'PYEOF'
#!/usr/bin/env python3
"""Attention-gated pooling module for cedar-gasket.

Contract: class AttentionGatedPooling(torch.nn.Module) with the exact attribute
names gate_a, gate_b, aggregate and methods attention_weights / forward.
forward(x) returns (pooled, weights) where weights is a (bag, 1) tensor of
softmax-normalized attention weights summing to one over the bag.
"""
import torch
import torch.nn as nn


class AttentionGatedPooling(nn.Module):
    def __init__(self, in_dim, gate_hidden, out_dim):
        super().__init__()
        self.in_dim = int(in_dim)
        self.gate_a = nn.Linear(int(in_dim), int(gate_hidden))
        self.gate_b = nn.Linear(int(gate_hidden), 1)
        self.aggregate = nn.Linear(int(in_dim), int(out_dim))

    def attention_weights(self, x):
        # x: (bag, in_dim) -> logits (bag,1) -> softmax over bag
        logits = self.gate_b(torch.tanh(self.gate_a(x)))
        return torch.softmax(logits, dim=0)

    def forward(self, x):
        weights = self.attention_weights(x)          # (bag, 1)
        pooled = self.aggregate((x * weights).sum(dim=0, keepdim=True))
        return pooled, weights
PYEOF
chmod +x /app/pooling.py

cat > /app/featurizer.py <<'PYEOF'
#!/usr/bin/env python3
"""Deterministic SMILES -> fixed-size float32 feature vectors using RDKit.

featurize_one maps a SMILES string to a (VEC_DIM,) float32 Morgan bit vector;
invalid / empty / whitespace-only input maps to the all-zero vector.
"""
import numpy as np
from rdkit import Chem
from rdkit import RDLogger
from rdkit.Chem import AllChem

RDLogger.DisableLog("rdApp.*")

VEC_DIM = 128
RADIUS = 2


def featurize_one(smiles):
    if not isinstance(smiles, str) or not smiles.strip():
        return np.zeros(VEC_DIM, dtype=np.float32)
    m = Chem.MolFromSmiles(smiles.strip())
    if m is None:
        return np.zeros(VEC_DIM, dtype=np.float32)
    bv = AllChem.GetMorganFingerprintAsBitVect(m, RADIUS, nBits=VEC_DIM)
    return np.array(list(bv), dtype=np.float32)


def featurize_smiles(smiles_list):
    return [featurize_one(s) for s in smiles_list]


if __name__ == "__main__":
    import sys
    for s in sys.argv[1:]:
        print(s, featurize_one(s).sum())
PYEOF
chmod +x /app/featurizer.py

# Produce the numeric deliverables by computing them (NOT by copying /tests).
python3 - <<'PYEOF'
#!/usr/bin/env python3
"""cedar-gasket oracle: builds /app/embeddings.npy (by fitting a category+role
model to /app/relations.json) and /app/smiles.npz (by RUNNING the agent-style
featurizer we wrote to /app/featurizer.py).
"""
import csv
import json
import os

import numpy as np

APP = "/app"


def load(path):
    with open(path) as fh:
        return json.load(fh)


def build_embeddings(rel, out_path):
    words = rel["words"]
    dim = int(rel["dim"])
    categories = rel["categories"]

    # Deterministic orthonormal per-category "topic" directions, plus one shared
    # adult->young offset direction.  adult = topic + 0.5*axis0,
    # young = topic - 0.5*axis0, so (a - b + c) lands exactly on the partner.
    rng = np.random.default_rng(len(categories))
    Q, _ = np.linalg.qr(rng.normal(size=(dim, len(categories))))
    alpha = float(dim) / 2.0
    axis = np.zeros(dim)
    axis[0] = 1.0

    vec = {}
    for ci, c in enumerate(categories):
        topic = alpha * Q[:, ci]
        vec[c["adult"]] = topic + 0.5 * axis
        vec[c["young"]] = topic - 0.5 * axis

    M = np.stack([vec[w] for w in words], axis=0).astype(np.float32)  # row i <-> words[i]
    np.save(out_path, M)
    print("embeddings.npy shape=%s dtype=%s" % (M.shape, M.dtype))
    return M


def build_smiles(out_name, feat_path):
    from importlib import util
    spec = util.spec_from_file_location("featurizer", feat_path)
    featurizer = util.module_from_spec(spec)
    spec.loader.exec_module(featurizer)
    with open(os.path.join(APP, "molecules.csv")) as fh:
        rows = list(csv.reader(fh))
    header = rows[0]
    smiles_col = header.index("smiles")
    body = [r for r in rows[1:] if r and len(r) > smiles_col and r[smiles_col].strip()]
    ids = [r[0].strip() for r in body]
    smiles = [r[smiles_col].strip() for r in body]
    X = np.stack([np.asarray(x, dtype=np.float32) for x in featurizer.featurize_smiles(smiles)])
    np.savez(out_name, X=X, ids=ids)
    print("smiles.npz shape=%s dtype=%s" % (X.shape, X.dtype))


def main():
    relations = load(os.path.join(APP, "relations.json"))
    build_embeddings(relations, "/app/embeddings.npy")
    build_smiles("/app/smiles.npz", "/app/featurizer.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PYEOF

echo "cedar-gasket deliverables produced OK" >&2