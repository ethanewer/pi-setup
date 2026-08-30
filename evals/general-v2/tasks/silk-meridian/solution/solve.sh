#!/bin/bash
# Real oracle for silk-meridian: writes the retrieval responder (/app/solve.py)
# and runs it on the visible bundle to produce /app/answer.json. Never reads
# /tests. Optional args (authoring-time expected generation):
#   bash solve.sh <manifest> <docs> <query> <out.json>
set -eu

MAN="${1:-/app/manifest.json}"
DOCS="${2:-/app/docs.json}"
QUERY="${3:-/app/query.txt}"
OUTJSON="${4:-/app/answer.json}"

SOLVER="/app/solve.py"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
"""Revision-pinned cosine retrieval responder for the Meridian stack."""
import json
import os
import sys

import numpy as np


def fail(msg):
    sys.stderr.write("solve.py: %s\n" % msg)
    sys.exit(2)


def main(manifest_path, docs_path, query_path, out_path):
    manifest_path = os.path.abspath(manifest_path)
    base_dir = os.path.dirname(manifest_path)
    with open(manifest_path) as fh:
        manifest = json.load(fh)
    with open(docs_path) as fh:
        docs = json.load(fh)["documents"]
    if not isinstance(docs, list) or not docs:
        fail("no documents")
    for d in docs:
        if not isinstance(d, dict) or "id" not in d or "text" not in d:
            fail("malformed document record")

    # ---- query -------------------------------------------------------------
    with open(query_path) as fh:
        raw = fh.read().splitlines()
    k = None
    q_lines = []
    for line in raw:
        s = line.strip()
        if s.lower().startswith("k="):
            k = int(s.split("=", 1)[1])
        else:
            q_lines.append(" ".join(s.split()))
    if k is None:
        fail("query.txt missing k=")
    query_text = " ".join(t for t in q_lines if t)

    # ---- model at the pinned revision ---------------------------------------
    model_dir = manifest["model_dir"]
    if model_dir not in sys.path:
        sys.path.insert(0, model_dir)
    import model as M

    weights_path = manifest["weights"]
    if not os.path.isabs(weights_path):
        weights_path = os.path.join(base_dir, weights_path)
    proj, weights_rev = M.load_weights(weights_path)
    pinned = manifest["revision"]
    if weights_rev != pinned:
        fail("revision mismatch: manifest pins %r but weights are %r"
             % (pinned, weights_rev))

    # ---- embeddings (cache only if its revision matches the pin) ------------
    docs_texts = [d["text"] for d in docs]
    ids = [d["id"] for d in docs]
    doc_vecs = None
    cache_path = os.path.join(base_dir, "cache", "doc_vectors.npz")
    if os.path.isfile(cache_path):
        try:
            z = np.load(cache_path, allow_pickle=True)
            if str(z["revision"]) == pinned:
                cached_ids = [str(x) for x in z["ids"]]
                if cached_ids == ids:
                    doc_vecs = z["vectors"].astype(np.float64)
                    n = np.sqrt((doc_vecs * doc_vecs).sum(axis=1, keepdims=True))
                    n[n == 0.0] = 1.0
                    doc_vecs = doc_vecs / n
        except Exception:
            doc_vecs = None
    if doc_vecs is None:
        doc_vecs = M.embed_texts(docs_texts, proj)
    q_vec = M.embed_texts([query_text], proj)[0]

    scores = {i: float(doc_vecs[j] @ q_vec) for j, i in enumerate(ids)}
    ranking = sorted(ids, key=lambda i: -scores[i])
    if not (1 <= k <= len(ids)):
        fail("k out of range")
    answer = {
        "revision": pinned,
        "ranking": ranking,
        "selected": ranking[k - 1],
        "scores": scores,
    }
    with open(out_path, "w") as fh:
        json.dump(answer, fh, indent=2)
    print("SOLVE_OK selected=%s" % answer["selected"])


if __name__ == "__main__":
    if len(sys.argv) != 5:
        fail("usage: solve.py <manifest> <docs> <query> <out.json>")
    main(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
PY

chmod +x "$SOLVER"

# ---- 2. Run the produced responder on the requested bundle -----------------
python3 "$SOLVER" "$MAN" "$DOCS" "$QUERY" "$OUTJSON"

echo "solve.sh done -> $SOLVER and $OUTJSON"
ls -l "$SOLVER" "$OUTJSON"
