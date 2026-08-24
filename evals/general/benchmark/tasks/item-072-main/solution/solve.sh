#!/bin/bash
# Oracle solution for item-072-main: write train.py and run it to produce the
# final model + metrics + sweep that satisfy both competing constraints.
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
SEED = 1

CONFIGS = [
    dict(dim=20, bucket=20000,   minn=2, maxn=4, epoch=25, lr=0.1, wordNgrams=2),
    dict(dim=20, bucket=100000,  minn=2, maxn=4, epoch=25, lr=0.1, wordNgrams=2),
    dict(dim=50, bucket=100000,  minn=2, maxn=4, epoch=25, lr=0.1, wordNgrams=2),
    dict(dim=100, bucket=2000000, minn=2, maxn=4, epoch=25, lr=0.1, wordNgrams=2),
]
REQ_ACC = 0.90
REQ_SIZE = 2_000_000

def to_ft(src, dst):
    df = pd.read_parquet(src)
    with open(dst, "w") as fh:
        for _, r in df.iterrows():
            lab = "__label__pos" if r["stars"] >= 4 else "__label__neg"
            fh.write("%s %s\n" % (lab, r["text"]))

def acc_of(model, ftpath):
    corr = tot = 0
    with open(ftpath) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            lab, _, rest = line.partition(" ")
            truth = lab.replace("__label__", "")
            pred = model.predict(rest, k=1)[0][0].replace("__label__", "")
            corr += pred == truth
            tot += 1
    return corr / tot

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
        results.append({
            "dim": cfg["dim"], "bucket": cfg["bucket"], "minn": cfg["minn"],
            "maxn": cfg["maxn"], "epoch": cfg["epoch"], "lr": cfg["lr"],
            "wordNgrams": cfg["wordNgrams"], "seed": SEED,
            "val_accuracy": round(acc_of(m, tval), 6),
            "model_size_bytes": os.path.getsize(binpath),
            "_bin": binpath,
        })

    results.sort(key=lambda e: e["model_size_bytes"])
    sweep = [{k: v for k, v in e.items() if k != "_bin"} for e in results]
    passers = [e for e in results
               if e["val_accuracy"] >= REQ_ACC and e["model_size_bytes"] <= REQ_SIZE]
    chosen = min(passers, key=lambda e: e["model_size_bytes"]) if passers \
        else max(results, key=lambda e: e["val_accuracy"])

    with open(os.path.join(OUT, "sweep.json"), "w") as fh:
        json.dump(sweep, fh, indent=2)
    chosen_out = {k: v for k, v in chosen.items() if k != "_bin"}
    with open(os.path.join(OUT, "metrics.json"), "w") as fh:
        json.dump(chosen_out, fh, indent=2)

    with open(chosen["_bin"], "rb") as src, open(os.path.join(OUT, "model.bin"), "wb") as dst:
        dst.write(src.read())
    print("final val_accuracy=%.4f size_bytes=%d dim=%d bucket=%d" % (
        chosen["val_accuracy"], chosen["model_size_bytes"], chosen["dim"], chosen["bucket"]))

if __name__ == "__main__":
    main()
PY

python3 /app/train.py
echo "solve completed"