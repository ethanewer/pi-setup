#!/bin/bash
# Verifier for cedar-gasket. Exercises every deliverable, including on hidden
# inputs from /tests/hidden, then writes a numeric reward to
# /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
python3 - <<'PYEOF' >&2
import csv, importlib.util, json, os

import numpy as np

failures = []

def log(*a):
    print("[verifier]", *a)

def load(path):
    with open(path) as fh:
        return json.load(fh)

def ref_featurize_one(smi):
    """Independent RDKit reference (identical contract as the task states)."""
    from rdkit import Chem
    from rdkit import RDLogger
    from rdkit.Chem import AllChem
    RDLogger.DisableLog("rdApp.*")
    if not isinstance(smi, str) or not smi.strip():
        return np.zeros(128, dtype=np.float32)
    m = Chem.MolFromSmiles(smi.strip())
    if m is None:
        return np.zeros(128, dtype=np.float32)
    bv = AllChem.GetMorganFingerprintAsBitVect(m, 2, nBits=128)
    return np.array(list(bv), dtype=np.float32)

# ------------------------------------------------------------------ pooling
def check_pooling():
    try:
        import torch
        spec = importlib.util.spec_from_file_location("pooling", "/app/pooling.py")
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
    except Exception as e:
        failures.append("pooling: cannot import: %r" % e)
        return
    Cls = getattr(mod, "AttentionGatedPooling", None)
    if Cls is None:
        failures.append("pooling: no AttentionGatedPooling class")
        return
    if not issubclass(Cls, torch.nn.Module):
        failures.append("pooling: class is not a torch.nn.Module")
        return
    params = load("/tests/hidden/pooling.json")
    obj = Cls(params["in_dim"], params["gate_hidden"], params["out_dim"])
    for attr in ("gate_a", "gate_b", "aggregate"):
        if not isinstance(getattr(obj, attr, None), torch.nn.Linear):
            failures.append("pooling: attr %r is not an nn.Linear" % attr)
    if not callable(getattr(obj, "attention_weights", None)):
        failures.append("pooling: missing callable attention_weights")
    for bag, seed in zip(params["bag_sizes"], params["seeds"]):
        torch.manual_seed(seed)
        x = torch.randn(bag, params["in_dim"])
        try:
            pooled, w = obj.forward(x)
        except Exception as e:
            failures.append("pooling: forward(bag=%d) raised %r" % (bag, e))
            continue
        if w.shape != (bag, 1):
            failures.append("pooling: weights shape %s != (%d,1)" % (w.shape, bag))
            continue
        s = float(w.detach().sum().item())
        if abs(s - 1.0) > 1e-4:
            failures.append("pooling: weights sum %.6f != 1 (bag=%d)" % (s, bag))
        if getattr(pooled, "shape", None) != (1, params["out_dim"]):
            failures.append("pooling: pooled shape %s != (1,%d)" % (pooled.shape, params["out_dim"]))
    try:
        w = obj.attention_weights(torch.randn(1, params["in_dim"]))
        if w.shape != (1, 1) or abs(float(w.detach().sum()) - 1.0) > 1e-4:
            failures.append("pooling: single-bag attention weights broken")
    except Exception as e:
        failures.append("pooling: single-bag raise %r" % e)

# --------------------------------------------------------------- embeddings
def check_embeddings():
    rel = load("/app/relations.json")
    words = rel["words"]
    dim = int(rel["dim"])
    if not os.path.exists("/app/embeddings.npy"):
        failures.append("embeddings: missing /app/embeddings.npy")
        return
    try:
        E = np.load("/app/embeddings.npy")
    except Exception as e:
        failures.append("embeddings: cannot load npy: %r" % e)
        return
    if E.dtype != np.float32:
        failures.append("embeddings: dtype %s, want float32" % E.dtype)
    if E.ndim != 2 or E.shape[1] != dim:
        failures.append("embeddings: shape %r, want (n,%d)" % (E.shape, dim))
        return
    if E.shape[0] != len(words):
        failures.append("embeddings: rows %d != %d words" % (E.shape[0], len(words)))
    emb = {w: np.asarray(E[i], dtype=np.float64) for i, w in enumerate(words)}
    norms = {w: (float(np.linalg.norm(v)) or 1.0) for w, v in emb.items()}

    def cos(u, uN, w):
        return float(u.dot(emb[w])) / (uN * norms.get(w, 1.0) + 1e-12)

    hidden = load("/tests/hidden/analog.json")["quadruples"]
    wins = 0.0
    for q in hidden:
        a, b, c, d = q["a"], q["b"], q["c"], q["d"]
        if not all(w in emb for w in q.values()):
            failures.append("embeddings: tuple references unknown word %r" % (q,))
            continue
        v = emb[a] - emb[b] + emb[c]
        vN = float(np.linalg.norm(v))
        exclude = {a, b, c}
        best, best_score = None, -9e9
        for w in words:
            if w in exclude:
                continue
            sc = cos(v, vN, w)
            if sc > best_score:
                best, best_score = w, sc
        second = max(cos(v, vN, w) for w in words if w not in exclude and w != best)
        if best != d:
            failures.append("embeddings: %s:%s,%s:%s -> predicted %r (score %.3f), want %r"
                            % (a, b, c, d, best, best_score, d))
        elif not (best_score > second + 1e-6):
            failures.append("embeddings: %s:%s,%s:%s tie (%.3f vs %.3f), not unique"
                            % (a, b, c, d, best_score, second))
        else:
            wins += 1.0
    if wins < len(hidden):
        failures.append("embeddings: hidden analogy win %.0f/%d" % (wins, len(hidden)))
    for c in rel["categories"]:
        sc = float(emb[c["adult"]].dot(emb[c["young"]]) /
                    (norms[c["adult"]] * norms[c["young"]] + 1e-12))
        if not (sc > 0.0):
            failures.append("embeddings: same-category %r/%r cos=%.3f" % (c["adult"], c["young"], sc))

# ---------------------------------------------------------------- featurizer
def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

def check_featurizer():
    try:
        mod = load_module("/app/featurizer.py", "featurizer")
    except Exception as e:
        failures.append("featurizer: cannot import: %r" % e)
        return
    if getattr(mod, "VEC_DIM", None) != 128:
        failures.append("featurizer: VEC_DIM != 128")
    fun = getattr(mod, "featurize_smiles", None)
    if not callable(fun):
        failures.append("featurizer: no featurize_smiles")
        return
    hidden = load("/tests/hidden/smiles.json")["smiles"]
    try:
        out1 = fun(hidden)
        out2 = fun(hidden)
    except Exception as e:
        failures.append("featurizer: raised: %r" % e)
        return
    if len(out1) != len(hidden):
        failures.append("featurizer: returned %d rows for %d smiles" % (len(out1), len(hidden)))
    for i, smi in enumerate(hidden):
        a = np.asarray(out1[i])
        b = np.asarray(out2[i])
        if a.shape != (128,):
            failures.append("featurizer: row %d (%r) shape %r" % (i, smi, a.shape))
        if a.dtype != np.float32:
            failures.append("featurizer: row %d dtype %r" % (i, a.dtype))
        if not np.array_equal(a, b):
            failures.append("featurizer: row %d not reproducible" % i)
        if not np.array_equal(a, ref_featurize_one(smi)):
            failures.append("featurizer: row %d (%r) != reference" % (i, smi))

def check_npz():
    if not os.path.exists("/app/smiles.npz"):
        failures.append("npz: missing /app/smiles.npz")
        return
    try:
        z = np.load("/app/smiles.npz", allow_pickle=True)
    except Exception as e:
        failures.append("npz: cannot load: %r" % e)
        return
    if "X" not in z or "ids" not in z:
        failures.append("npz: missing X/ids")
        return
    X = z["X"]; ids = list(z["ids"])
    if X.ndim != 2 or X.shape[1] != 128:
        failures.append("npz: X shape %r want (n,128)" % (X.shape,))
    if X.dtype != np.float32:
        failures.append("npz: X dtype %r want float32" % X.dtype)
    rows = list(csv.reader(open("/app/molecules.csv")))
    hdr = rows[0]; scol = hdr.index("smiles")
    body = [r for r in rows[1:] if r and len(r) > scol and r[scol].strip()]
    vids = [r[0].strip() for r in body]
    vsmi = [r[scol].strip() for r in body]
    if list(ids) != vids:
        failures.append("npz: ids order mismatch visible catalog")
    if len(X) != len(vids):
        failures.append("npz: %d rows for %d molecules" % (len(X), len(vids)))
    try:
        mod = load_module("/app/featurizer.py", "featurizer2")
        Xref = np.stack([np.asarray(x, dtype=np.float32) for x in mod.featurize_smiles(vsmi)])
        if not np.array_equal(X[:len(vids)], Xref):
            failures.append("npz: X does not match own featurizer on visible catalog")
    except Exception as e:
        failures.append("npz: consistency error %r" % e)
    if X.shape[0] >= 2 and len({tuple(r) for r in X[:len(vids)]}) < 2:
        failures.append("npz: X rows all identical (featurization vacuous)")

import csv

check_pooling()
check_embeddings()
check_featurizer()
check_npz()

reward = 0 if failures else 1
with open("/logs/verifier/reward.txt", "w") as fh:
    fh.write(str(reward) + "\n")
print("reward=%d failures=%d" % (reward, len(failures)))
for f in failures[:50]:
    print("  -", f)
PYEOF