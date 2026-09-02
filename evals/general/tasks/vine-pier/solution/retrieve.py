#!/usr/bin/env python3
"""retrieve.py -- revision-pinned document embedding + cosine ranking.

Encodes each document and the query as the (L2-normalized) mean of their token
embeddings from the checkpoint's "emb" matrix at the pinned model revision,
ranks documents by cosine similarity to the query (descending; ties broken by
lower document index) and reports the ranking, the selected document, and the
5th-ranked document.

Usage:
  python /app/retrieve.py --model <ckpt> --docs "s0;s1" --query "a,b" [--out FILE]
where each document is a comma-separated token-id list, and --docs is the list
separated by ';'.  JSON written to --out (default /app/ranks.json).
"""
import argparse
import json
import struct
import numpy as np


def load_emb(path):
    b = open(path, "rb").read()
    off = 8
    V = struct.unpack_from("<I", b, off)[0]; off += 4
    nt = struct.unpack_from("<I", b, off)[0]; off += 4
    mg = struct.unpack_from("<I", b, off)[0]; off += 4
    de = struct.unpack_from("<I", b, off)[0]; off += 4
    rl = struct.unpack_from("<I", b, off)[0]; off += 4
    rev = b[off:off + rl].decode("ascii"); off += rl
    emb = None
    for _ in range(nt):
        nl = struct.unpack_from("<I", b, off)[0]; off += 4
        nm = b[off:off + nl].decode("ascii"); off += nl
        dt = struct.unpack_from("<B", b, off)[0]; off += 1
        nd = struct.unpack_from("<B", b, off)[0]; off += 1
        shp = struct.unpack_from("<%dI" % nd, b, off); off += 4 * nd
        n = int(np.prod(shp))
        arr = np.frombuffer(b[off:off + 4 * n], dtype="float32").reshape(shp).copy()
        off += 4 * n
        if nm == "emb":
            emb = arr
    return emb, rev


def embed(emb, ids):
    if not ids:
        v = np.zeros(emb.shape[1], dtype="float64")
    else:
        v = emb[np.asarray(ids)].sum(axis=0).astype("float64")
    n = np.linalg.norm(v)
    return v if n == 0 else v / n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--docs", required=True, help="';'-separated doc id lists")
    ap.add_argument("--query", required=True, help="comma-separated query")
    ap.add_argument("--out", default="/app/ranks.json")
    args = ap.parse_args()

    emb, rev = load_emb(args.model)
    docs = []
    for d in args.docs.split(";"):
        docs.append([int(x) for x in d.split(",") if x != ""])
    query = [int(x) for x in args.query.split(",") if x != ""]

    qv = embed(emb, query)
    scored = []
    for i, dids in enumerate(docs):
        dv = embed(emb, dids)
        cos = float(np.dot(dv, qv)) if (np.linalg.norm(dv) and np.linalg.norm(qv)) else 0.0
        scored.append((i, cos))
    scored.sort(key=lambda t: (-t[1], t[0]))

    rank = [{"doc": i, "position": p, "cosine": round(cos, 6)}
            for p, (i, cos) in enumerate(scored, start=1)]

    result = {
        "ckpt": args.model,
        "revision": rev,
        "query": query,
        "docs": docs,
        "embedding_dim": int(emb.shape[1]),
        "rank": rank,
        "selected": scored[0][0],
        "fifth": scored[4][0] if len(scored) >= 5 else None,
    }
    with open(args.out, "w") as fh:
        json.dump(result, fh)
    print(json.dumps({"selected": result["selected"]}))


if __name__ == "__main__":
    main()