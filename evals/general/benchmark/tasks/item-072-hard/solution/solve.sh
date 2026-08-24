#!/bin/bash
# Oracle solution for item-072-hard: write train.py and run it to produce the
# final model + metrics + sweep satisfying all three competing constraints
# (overall accuracy, model size cap, and positive-class recall).
set -euo pipefail
mkdir -p /app/output

cat > /app/train.py <<'PY'
#!/usr/bin/env python3
import json
import os
import fasttext
import pandas as pd

DATA = "/app/data"
OUT = "/app/output"
SEED = 7

CONFIGS = [
    dict(dim=20, bucket=20000,    minn=2, maxn=4, epoch=25, lr=0.1, wordNgrams=2),
    dict(dim=20, bucket=100000,   minn=2, maxn=4, epoch=25, lr=0.1, wordNgrams=2),
    dict(dim=50, bucket=100000,   minn=2, maxn=4, epoch=25, lr=0.1, wordNgrams=2),
    dict(dim=20, bucket=1000000,  minn=2, maxn=4, epoch=25, lr=0.1, wordNgrams=2),
    dict(dim=100, bucket=2000000, minn=2, maxn=4, epoch=25, lr=0.1, wordNgrams=2),
]
REQ_ACC = 0.86
REQ_SIZE = 2_000_000
REQ_POS = 0.78

def to_ft(src, dst):
    df = pd.read_parquet(src)
    with open(dst, "w") as fh:
        for _, r in df.iterrows():
            lab = "__label__pos" if r["stars"] >= 4 else "__label__neg"
            fh.write("%s %s\n" % (lab, r["text"]))

def class_stats(model, ftpath):
    both = {k: [0, 0] for k in ["pos", "neg"]}
    with open(ftpath) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            lab, _, rest = line.partition(" ")
            truth = lab.replace("__label__", "")
            pred = model.predict(rest, k=1)[0][0].replace("__label__", "")
            both[truth][1] += 1
            both[truth][0] += pred == truth
    total = sum(v[1] for v in both.values())
    correct = sum(v[0] for v in both.values())
    return {
        "val_accuracy": round(correct / total, 6),
        "pos_recall": round(both["pos"][0] / both["pos"][1], 6),
        "neg_recall": round(both["neg"][0] / both["neg"][1], 6),
    }

def main():
    os.makedirs(OUT, exist_ok=True)
    ttrain = os.path.join(DATA, "train.txt")
    tval = os.path.join(DATA, "val.txt")
    to_ft(os.path.join(DATA, "train.parquet"), ttrain)
    to_ft(os.path.join(DATA, "val.parquet"), tval)

    results = []
    for i, cfg in enumerate(CONFIGS):
        binpath = os.path.join(DATA, "tmp_model_%d.bin" % i)
        m = fasttext.train_supervised(ttrain, seed=SEED, verbose=0, **cfg)
        m.save_model(binpath)
        stats = class_stats(m, tval)
        results.append({
            "dim": cfg["dim"], "bucket": cfg["bucket"], "minn": cfg["minn"],
            "maxn": cfg["maxn"], "epoch": cfg["epoch"], "lr": cfg["lr"],
            "wordNgrams": cfg["wordNgrams"], "seed": SEED,
            "model_size_bytes": os.path.getsize(binpath),
            "val_accuracy": stats["val_accuracy"],
            "pos_recall": stats["pos_recall"],
            "neg_recall": stats["neg_recall"],
            "_bin": binpath,
        })

    results.sort(key=lambda e: e["model_size_bytes"])
    sweep = [{k: v for k, v in e.items() if k != "_bin"} for e in results]
    passers = [e for e in results if e["val_accuracy"] >= REQ_ACC and e["model_size_bytes"] <= REQ_SIZE
               and e["pos_recall"] >= REQ_POS]
    chosen = min(passers, key=lambda e: e["model_size_bytes"]) if passers \
        else max(results, key=lambda e: e["val_accuracy"])

    with open(os.path.join(OUT, "sweep.json"), "w") as fh:
        json.dump(sweep, fh, indent=2)
    chosen_out = {k: v for k, v in chosen.items() if k != "_bin"}
    with open(os.path.join(OUT, "metrics.json"), "w") as fh:
        json.dump(chosen_out, fh, indent=2)

    with open(chosen["_bin"], "rb") as src, open(os.path.join(OUT, "model.bin"), "wb") as dst:
        dst.write(src.read())
    print("final size=%d acc=%.4f pos_recall=%.4f neg_recall=%.4f dim=%d bucket=%d" % (
        chosen["model_size_bytes"], chosen["val_accuracy"], chosen["pos_recall"],
        chosen["neg_recall"], chosen["dim"], chosen["bucket"]))

if __name__ == "__main__":
    main()
PY

python3 /app/train.py
echo "solve completed"