#!/usr/bin/env python3
"""field-map.py — map each form field to the best-matching document chunk
using TF-IDF cosine retrieval, and record per-field + aggregate statistics.

Usage:
  python3 /app/field-map.py [-f FIELDS_DIR] [-c CHUNKS_DIR] [-m MAP_JSON] [-s STATS_JSON]
Defaults: fields=/app/fields chunks=/app/chunks map=/app/field-map.json
          stats=/app/retrieval-stats.json
map JSON =  [{"field": id, "chunk": id|null, "score": float}, ...] sorted by field.
stats JSON:
  {
    "num_fields": N, "num_chunks": C,
    "per_field": { field: {"best_chunk": id|null, "best_score": float,
                           "mean_score": float, "candidate_count": C,
                           "top_scores": [3 floats desc]} },
    "aggregate": {"mean_best_score": float, "median_best_score": float}
  }
A field whose text has no tokens maps to chunk=null with score 0.0.
Ties between chunks break alphabetically (lowest sorted chunk id wins).
"""
import json, os, sys
from sklearn.feature_extraction.text import TfidfVectorizer
import numpy as np


def read_txts(d):
    if not os.path.isdir(d):
        return [], []
    names = [n for n in os.listdir(d) if n.endswith(".txt")]
    names.sort()
    return names, [" ".join(open(os.path.join(d, n)).read().split()) for n in names]


def compute(fdir, cdir):
    fnames, ftxt = read_txts(fdir)
    cnames, ctxt = read_txts(cdir)
    mapping, per = [], {}
    if not fnames or not cnames:
        stats = {"num_fields": len(fnames), "num_chunks": len(cnames),
                 "per_field": {},
                 "aggregate": {"mean_best_score": 0.0, "median_best_score": 0.0}}
        return mapping, stats
    if all(t == "" for t in ctxt):
        raise ValueError("chunk corpus must contain non-empty text")
    vec = TfidfVectorizer()
    C = vec.fit_transform(ctxt).toarray()
    F = vec.transform(ftxt).toarray()
    for fn, fv in zip(fnames, F):
        fid = fn[:-4] if fn.endswith(".txt") else fn
        if float(np.sum(np.abs(fv))) == 0.0:
            mapping.append({"field": fid, "chunk": None, "score": 0.0})
            per[fid] = {"best_chunk": None, "best_score": 0.0, "mean_score": 0.0,
                       "candidate_count": len(cnames), "top_scores": [0.0]}
            continue
        scores = C @ fv
        j = int(np.argmax(scores))           # first max = lowest sorted index (tie-break)
        cid = cnames[j][:-4] if cnames[j].endswith(".txt") else cnames[j]
        mapping.append({"field": fid, "chunk": cid, "score": float(scores[j])})
        per[fid] = {"best_chunk": cid, "best_score": float(scores[j]),
                   "mean_score": float(scores.mean()),
                   "candidate_count": len(cnames),
                   "top_scores": sorted([float(x) for x in scores], reverse=True)[:3]}
    bests = [m["score"] for m in mapping]
    stats = {"num_fields": len(fnames), "num_chunks": len(cnames), "per_field": per,
             "aggregate": {"mean_best_score": float(np.mean(bests)) if bests else 0.0,
                           "median_best_score": float(np.median(bests)) if bests else 0.0}}
    return mapping, stats


def arg_get(args, flag, default):
    for i in range(len(args) - 1):
        if args[i] == flag:
            return args[i + 1]
    return default


def main():
    args = sys.argv[1:]
    fdir = arg_get(args, "-f", "/app/fields")
    cdir = arg_get(args, "-c", "/app/chunks")
    mapout = arg_get(args, "-m", "/app/field-map.json")
    statsout = arg_get(args, "-s", "/app/retrieval-stats.json")
    mapping, stats = compute(fdir, cdir)
    with open(mapout, "w") as fh:
        json.dump(mapping, fh, indent=2)
    with open(statsout, "w") as fh:
        json.dump(stats, fh, indent=2)


if __name__ == "__main__":
    main()