#!/bin/bash
# Oracle for aurora-reef: write the generic embedding builder, then RUN it on
# the visible fixture to produce /app/embeddings.npy. Never reads /tests.
set -eu

BUILDER="/app/build_embeddings.py"
OUT="/app/embeddings.npy"

cat > "$BUILDER" <<'PY'
#!/usr/bin/env python3
"""Generic clan-dialect embedding builder.

Construction: each clan gets its own orthogonal direction p_i; one shared
shift direction u (orthogonal to every p_i) encodes elder->calf, with
v(calf) = v(elder) + u.  Cross-clan analogies then solve exactly by
cosine ranking, and same-clan pairs are strictly more similar than
cross-clan pairs.
"""
import json
import sys

import numpy as np


def main():
    rel_path, out_path = sys.argv[1], sys.argv[2]
    with open(rel_path, "r", encoding="utf-8") as fh:
        rel = json.load(fh)

    words = rel["words"]
    cats = rel["categories"]
    dim = int(rel["dim"])
    n = len(words)
    ncat = len(cats)

    # Fixed-seed orthonormal basis; take 1 shift direction + ncat clan dirs.
    rng = np.random.default_rng(20240517)
    basis_rows = max(n + 8, 16)
    m = rng.standard_normal((basis_rows, dim))
    q, _ = np.linalg.qr(m.T)          # q: (dim, basis_rows) orthonormal cols
    shift = q[:, 0]
    clan_dirs = q[:, 1:1 + ncat]

    elder_vec = {c["elder"]: clan_dirs[:, i] for i, c in enumerate(cats)}
    calf_vec = {c["calf"]: clan_dirs[:, i] + shift for i, c in enumerate(cats)}

    rows = np.zeros((n, dim), dtype=np.float32)
    for i, w in enumerate(words):
        if w in elder_vec:
            rows[i] = elder_vec[w]
        elif w in calf_vec:
            rows[i] = calf_vec[w]
        else:
            rows[i] = q[:, (1 + ncat + i) % q.shape[1]]
    np.save(out_path, rows.astype(np.float32))


if __name__ == "__main__":
    main()
PY
chmod +x "$BUILDER"

python3 "$BUILDER" /app/relations.json "$OUT"

echo "solve.sh done -> $BUILDER and $OUT"
ls -l "$BUILDER" "$OUT"
