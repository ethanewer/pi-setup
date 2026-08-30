#!/bin/bash
# Verifier for saffron-rune: imports the deliverable /app/featurize.py, runs
# featurize_column on hidden SMILES lists and byte-compares against an
# independent reference implementation of the documented algorithm; checks
# /app/features.npz against the visible catalog. Writes REWARD (0/1) to
# /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import csv, importlib.util, json, os, sys

import numpy as np

failures = []


def log(*a):
    print("[verifier]", *a)


# ---------------- independent reference (documented algorithm) -------------
REF_DIM = 96
REF_ALLOWED = set(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789()[]+=#%@/.$-"
)


def ref_one(smiles):
    if not isinstance(smiles, str):
        return np.zeros(REF_DIM, dtype=np.float32)
    s = smiles.strip()
    if not s:
        return np.zeros(REF_DIM, dtype=np.float32)
    if any(ch not in REF_ALLOWED for ch in s):
        return np.zeros(REF_DIM, dtype=np.float32)
    tokens = []
    i, n = 0, len(s)
    while i < n:
        if s[i] == "[":
            j = s.find("]", i + 1)
            if j == -1:
                return np.zeros(REF_DIM, dtype=np.float32)
            tokens.append(s[i:j + 1])
            i = j + 1
        elif s[i:i + 2] in ("Cl", "Br"):
            tokens.append(s[i:i + 2])
            i += 2
        else:
            tokens.append(s[i])
            i += 1
    x = np.zeros(REF_DIM, dtype=np.float64)
    for pos, tok in enumerate(tokens):
        tid = 0
        for ch in tok:
            tid = (tid * 131 + ord(ch)) % 1000003
        x[(pos * 31 + tid) % REF_DIM] += 1.0
    return x.astype(np.float32)


def ref_column(lst):
    return [ref_one(s) for s in lst]


# ---------------- import the agent's module ----------------
spec = importlib.util.spec_from_file_location("agent_featurize", "/app/featurize.py")
try:
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
except Exception as e:
    failures.append("featurize.py: cannot import: %r" % e)
    print("verify failures:", failures)
    sys.exit(1)

if getattr(mod, "VEC_DIM", None) != 96:
    failures.append("VEC_DIM != 96")
for fn in ("featurize_one", "featurize_column"):
    if not callable(getattr(mod, fn, None)):
        failures.append("missing callable %s" % fn)

if failures:
    print("verify failures:", failures)
    sys.exit(1)


def arrays_match(a, b):
    try:
        if a.shape != b.shape or a.dtype != np.float32:
            return False
        return a.tobytes() == b.tobytes()
    except Exception:
        return False


# ---------------- reproducibility on visible catalog ----------------
try:
    rows = list(csv.DictReader(open("/app/molecules.csv", newline="", encoding="utf-8")))
except Exception as e:
    rows = None
    failures.append("cannot read /app/molecules.csv: %r" % e)

if rows is not None:
    col = [r["smiles"] for r in rows]
    try:
        got = mod.featurize_column(col)
        want = ref_column(col)
        if not isinstance(got, list) or len(got) != len(col):
            failures.append("featurize_column visible: wrong length")
        else:
            for i, (g, w) in enumerate(zip(got, want)):
                if not arrays_match(np.asarray(g), w):
                    failures.append("visible row %d (%r) mismatch" % (i, col[i]))
        again = mod.featurize_column(col)
        for i, (g, h) in enumerate(zip(got, again)):
            if not arrays_match(np.asarray(g), np.asarray(h)):
                failures.append("visible row %d not reproducible" % i)
    except Exception as e:
        failures.append("featurize_column visible raised: %r" % e)

# ---------------- hidden SMILES lists ----------------
hidden_dir = "/tests/hidden"
cases = sorted(f for f in os.listdir(hidden_dir) if f.endswith(".json")) if os.path.isdir(hidden_dir) else []
if not cases:
    failures.append("no hidden cases present")
for fn in cases:
    try:
        with open(os.path.join(hidden_dir, fn)) as fh:
            lst = json.load(fh)
        if not isinstance(lst, list) or not all(isinstance(x, str) for x in lst):
            failures.append("hidden %s: bad fixture" % fn)
            continue
    except Exception as e:
        failures.append("hidden %s unreadable: %r" % (fn, e))
        continue
    try:
        got = mod.featurize_column(lst)
        want = ref_column(lst)
        if not isinstance(got, list) or len(got) != len(lst):
            failures.append("hidden %s: wrong length" % fn)
            continue
        for i, (g, w) in enumerate(zip(got, want)):
            g = np.asarray(g)
            if g.shape != (96,) or g.dtype != np.float32:
                failures.append("hidden %s item %d: shape/dtype %s/%s" % (fn, i, g.shape, g.dtype))
            elif not arrays_match(g, w):
                failures.append("hidden %s item %d (%r) mismatch" % (fn, i, lst[i]))
        again = mod.featurize_column(lst)
        for g, h in zip(got, again):
            if not arrays_match(np.asarray(g), np.asarray(h)):
                failures.append("hidden %s: not reproducible" % fn)
                break
    except Exception as e:
        failures.append("hidden %s raised: %r" % (fn, e))

# ---------------- /app/features.npz vs visible catalog ----------------
if os.path.isfile("/app/features.npz"):
    try:
        z = np.load("/app/features.npz", allow_pickle=False)
        X, ids = z["X"], z["ids"]
        if rows is not None:
            if X.shape != (len(rows), 96):
                failures.append("features.npz X shape %s != (%d, 96)" % (X.shape, len(rows)))
            elif X.dtype != np.float32:
                failures.append("features.npz X dtype %s != float32" % X.dtype)
            else:
                want = np.stack(ref_column([r["smiles"] for r in rows]))
                if X.tobytes() != want.tobytes():
                    failures.append("features.npz X does not match reference")
            want_ids = np.array([r["id"] for r in rows])
            if ids.tolist() != want_ids.tolist():
                failures.append("features.npz ids mismatch")
    except Exception as e:
        failures.append("features.npz unreadable: %r" % e)
else:
    failures.append("missing /app/features.npz")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
