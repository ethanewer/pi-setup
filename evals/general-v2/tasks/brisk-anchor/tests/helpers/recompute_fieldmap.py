#!/usr/bin/env python3
"""Recompute the TF-IDF field->chunk mapping + stats for a fields dir and a
chunks dir using the documented procedure. Called by tests/test.sh to verify
the deliverable /app/field-map.py independently.
Prints two JSON docs: first the mapping list, second the stats object.
"""
import json, os, sys
from sklearn.feature_extraction.text import TfidfVectorizer
import numpy as np


def read_txts(d):
    names = sorted(n for n in os.listdir(d) if n.endswith(".txt"))
    return names, [" ".join(open(os.path.join(d, n)).read().split()) for n in names]


def compute(fdir, cdir):
    fnames, ftxt = read_txts(fdir)
    cnames, ctxt = read_txts(cdir)
    mapping, per = [], {}
    if not fnames or not cnames:
        return mapping, {"num_fields": len(fnames), "num_chunks": len(cnames),
                         "per_field": {},
                         "aggregate": {"mean_best_score": 0.0, "median_best_score": 0.0}}
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
        j = int(np.argmax(scores))
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


def main():
    fdir, cdir = sys.argv[1], sys.argv[2]
    mapping, stats = compute(fdir, cdir)
    json.dump(mapping, sys.stdout)
    sys.stdout.write("\n")
    json.dump(stats, sys.stdout)


if __name__ == "__main__":
    main()