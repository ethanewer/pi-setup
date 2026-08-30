#!/usr/bin/env python3
"""Deterministic case-bundle generator for the silk-meridian task.

Produces a self-contained retrieval case:
  <out>/manifest.json          pins the revision and the weights path
  <out>/model/weights.npz      projection matrix + embedded revision string
  <out>/docs.json              documents {"id", "text"}
  <out>/query.txt              "k=<int>" first line, query text after
  <out>/cache/doc_vectors.npz  (stale) cached vectors + stale revision

Visible bundle: --out /app.  Hidden bundles: --out <case dir> with absolute
weights path recorded in the manifest.
"""
import argparse
import json
import os

import numpy as np

THEMES = {
    "orchard": ["apple scab lesions on the young grafts", "dormant oil spray before bud break",
                "honeybee hives arrived at the north rows", "late frost nipped the pear blossoms",
                "cider press calibration and pomace disposal", "canopy thinning improves sun exposure"],
    "marine": ["sonar contact drifting near the shelf break", "buoy array reported a warm anomaly",
               "trawl nets mended before the spring season", "kelp canopy mapped by the dive team",
               "tide gauge logged an unusual seiche", "larval counts spiked in the estuary samples"],
    "rail": ["freight cars re-weighed at the hump yard", "switch heater failed during the storm",
             "track geometry car found a crosslevel fault", "gravel ballast dropped at milepost forty",
             "dispatcher notes congestion on the single line", "axle bearing alarms cleared at dawn"],
    "apiary": ["varroa mite wash counts above threshold", "queen cells spotted in the supers",
               "smoker fuel switched to burlap", "robber bees at the honey house door",
               "frame wax cappings melted for trade", "hive stands lifted above the damp ground"],
    "foundry": ["crucible lining replaced after the burn-through", "green sand moisture drifting high",
                "pattern plates re-coated with release agent", "shakeout drum bearings running hot",
                "inoculant blocks added at the ladle", "casting porosity traced to the vent pins"],
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--name", required=True)
    ap.add_argument("--revision", required=True)
    ap.add_argument("--stale-revision", required=True)
    ap.add_argument("--stale-seed", type=int, required=True)
    ap.add_argument("--n-docs", type=int, default=14)
    args = ap.parse_args()

    rng = np.random.default_rng(args.seed)
    out = os.path.abspath(args.out)
    os.makedirs(os.path.join(out, "model"), exist_ok=True)
    os.makedirs(os.path.join(out, "cache"), exist_ok=True)

    # ---- documents --------------------------------------------------------
    theme_names = sorted(THEMES)
    t1, t2 = rng.choice(len(theme_names), size=2, replace=False)
    lines1 = list(THEMES[theme_names[t1]])
    lines2 = list(THEMES[theme_names[t2]])
    docs = []
    for i in range(args.n_docs):
        if i % 2 == 0:
            src, j = lines1, (i // 2) % len(lines1)
        else:
            src, j = lines2, (i // 2) % len(lines2)
        text = src[j]
        if i % 4 >= 2:
            text = text + "; " + src[(j + 3) % len(src)]
        docs.append({"id": "doc-%02d" % (i + 1), "text": text})
    ids = [d["id"] for d in docs]
    texts = [d["text"] for d in docs]

    # ---- weights at the pinned revision -----------------------------------
    proj = rng.normal(0.0, 1.0 / np.sqrt(256.0), (256, 32))
    np.savez(os.path.join(out, "model", "weights.npz"),
             proj=proj.astype(np.float64),
             revision=np.array(args.revision))

    # ---- query: a paraphrase-ish excerpt of one document ------------------
    target = docs[int(rng.integers(0, len(docs)))]
    words = target["text"].replace(";", " ").split()
    k = int(rng.integers(1, len(docs) + 1))
    query_text = " ".join(words[:max(4, int(len(words) * 0.6))])

    with open(os.path.join(out, "docs.json"), "w") as fh:
        json.dump({"documents": docs}, fh, indent=2)
    with open(os.path.join(out, "query.txt"), "w") as fh:
        fh.write("k=%d\n%s\n" % (k, query_text))

    manifest = {
        "model_dir": "/app/model",
        # relative to the manifest's directory (resolvable anywhere)
        "weights": "model/weights.npz",
        "revision": args.revision,
        "metric": "cosine",
    }
    with open(os.path.join(out, "manifest.json"), "w") as fh:
        json.dump(manifest, fh, indent=2)

    # ---- stale cache -------------------------------------------------------
    # sanity: the stale revision must give a DIFFERENT ordering, otherwise the
    # cache trap is not a trap (deterministic seeds keep this stable).
    import sys
    sys.path.insert(0, "/app/model")
    import model as M

    def rank_with(p):
        V = M.embed_texts(texts, p)
        q = M.embed_texts([query_text], p)[0]
        order = np.argsort(-(V @ q), kind="stable")
        return [ids[i] for i in order]

    cur = rank_with(proj)
    old_rng = np.random.default_rng(args.stale_seed)
    old_proj = old_rng.normal(0.0, 1.0 / np.sqrt(256.0), (256, 32))
    old = rank_with(old_proj)
    if out == "/app":
        assert old != cur, "stale cache would not change the answer; bump --stale-seed"
    np.savez(os.path.join(out, "cache", "doc_vectors.npz"),
             ids=np.array(ids, dtype=object),
             vectors=M.embed_texts(texts, old_proj).astype(np.float32),
             revision=np.array(args.stale_revision))

    print("bundle %s: %d docs, k=%d, revision=%s -> %s"
          % (args.name, len(docs), k, args.revision, out))


if __name__ == "__main__":
    main()
