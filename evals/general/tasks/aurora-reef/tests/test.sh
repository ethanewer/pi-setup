#!/bin/bash
# Verifier for aurora-reef: enforces the no-modify rule on /app/relations.json,
# checks the visible /app/embeddings.npy, and EXECUTES /app/build_embeddings.py
# on hidden relations files, verifying analogy ranking and similarity on every
# cross-clan quadruple in both orientations. Writes REWARD (0/1) to
# /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

if [ ! -f /app/relations.json ]; then
    echo "no-modify: /app/relations.json missing" >&2
    REL_OK=0
else
    actual="$(sha256sum /app/relations.json | awk '{print $1}')"
    expected="e07862f1c0ece47bd1c14ca172dd1677d90eaaa272838de23ddd2befd1412176"
    if [ "$actual" != "$expected" ]; then
        echo "no-modify: /app/relations.json was modified" >&2
        REL_OK=0
    else
        REL_OK=1
    fi
fi

python3 - "$REL_OK" <<'PY'
import itertools, json, os, subprocess, sys

import numpy as np

BUILDER = "/app/build_embeddings.py"
failures = []
if int(sys.argv[1]) != 1:
    failures.append("no-modify: /app/relations.json missing or modified")


def check_matrix(E, rel, quads, tag):
    words = rel["words"]
    dim = int(rel["dim"])
    if not isinstance(E, np.ndarray) or E.dtype != np.float32:
        failures.append("%s: dtype %s, want float32" % (tag, getattr(E, "dtype", None)))
        return
    if E.ndim != 2 or E.shape != (len(words), dim):
        failures.append("%s: shape %r, want (%d,%d)" % (tag, E.shape, len(words), dim))
        return
    emb = {w: np.asarray(E[i], dtype=np.float64) for i, w in enumerate(words)}
    norms = {w: float(np.linalg.norm(v)) for w, v in emb.items()}
    if any(nrm < 1e-9 for nrm in norms.values()):
        failures.append("%s: zero-norm row present" % tag)
        return

    def cos(u, w):
        return float(np.dot(u, emb[w])) / ((float(np.linalg.norm(u)) or 1.0) * norms[w])

    # every cross-clan quadruple, both orientations
    cats = rel["categories"]
    tested = 0
    for ci, cj in itertools.permutations(range(len(cats)), 2):
        ea, ca = cats[ci]["elder"], cats[ci]["calf"]
        eb, cb = cats[cj]["elder"], cats[cj]["calf"]
        for a, b, c, d in ((ea, ca, eb, cb), (ca, ea, cb, eb)):
            q = emb[b] - emb[a] + emb[c]
            if float(np.linalg.norm(q)) < 1e-9:
                failures.append("%s: zero query for %s" % (tag, (a, b, c, d)))
                continue
            exclude = {a, b, c}
            best, best_w = -9e9, None
            for w in words:
                if w in exclude:
                    continue
                s = cos(q, w)
                if s > best:
                    best, best_w = s, w
            tested += 1
            if best_w != d:
                failures.append("%s: analogy %s->%s | %s->? ranked %r (want %r)"
                                % (tag, a, b, c, best_w, d))
    if tested == 0:
        failures.append("%s: no quadruples tested" % tag)

    # similarity: same-clan > 0 and > every cross-clan pair
    for cat in cats:
        s_same = cos(emb[cat["elder"]], cat["calf"])
        if s_same <= 0.0:
            failures.append("%s: clan %r elder/calf cos %.4f not positive"
                            % (tag, cat["name"], s_same))
            continue
        others = [w for w in words if w not in (cat["elder"], cat["calf"])]
        for w in others:
            s_cross = cos(emb[cat["elder"]], w)
            if s_cross >= s_same:
                failures.append("%s: clan %r: cross cos %.4f >= same cos %.4f"
                                % (tag, cat["name"], s_cross, s_same))
                break


if not os.path.isfile(BUILDER):
    failures.append("missing /app/build_embeddings.py")
else:
    # --- visible deliverable: /app/embeddings.npy ---
    if not os.path.isfile("/app/embeddings.npy"):
        failures.append("missing /app/embeddings.npy")
    else:
        try:
            with open("/app/relations.json") as fh:
                vis_rel = json.load(fh)
            E = np.load("/app/embeddings.npy")
            vis_quads = vis_rel.get("quadruples", [])
            check_matrix(E, vis_rel, vis_quads, "visible")
        except Exception as e:
            failures.append("visible embeddings failed to load/check: %r" % e)

    # --- hidden cases: run the builder unchanged on fresh relation files ---
    hidden_dir = "/tests/hidden"
    for case in sorted(os.listdir(hidden_dir)) if os.path.isdir(hidden_dir) else []:
        base = os.path.join(hidden_dir, case)
        rel_path = os.path.join(base, "relations.json")
        if not os.path.isfile(rel_path):
            failures.append("hidden %r: no relations.json" % case)
            continue
        out = "/tmp/aurora_reef_%s.npy" % case
        if os.path.exists(out):
            os.remove(out)
        try:
            r = subprocess.run([sys.executable, BUILDER, rel_path, out],
                               capture_output=True, text=True, timeout=120)
        except subprocess.TimeoutExpired:
            failures.append("hidden %r: builder timed out" % case)
            continue
        if r.returncode != 0 or not os.path.exists(out):
            failures.append("hidden %r: builder failed rc=%s err=%.200s"
                            % (case, r.returncode, r.stderr))
            continue
        try:
            with open(rel_path) as fh:
                rel = json.load(fh)
            check_matrix(np.load(out), rel, rel.get("quadruples", []), "hidden/%s" % case)
        except Exception as e:
            failures.append("hidden %r: check raised %r" % (case, e))

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
