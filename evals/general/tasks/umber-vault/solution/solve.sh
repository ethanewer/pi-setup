#!/usr/bin/env bash
# Oracle for umber-vault. Writes the four pipeline scripts into /app and then
# RUNS the real pipeline end-to-end: deterministic split -> train a snapshot ->
# fine-tune a fold -> single-label predictions -> streaming large-bag scores.
set -euo pipefail
cd /app

# ---- 1. install the pipeline scripts -------------------------------------
cp -f /solution/split.py /solution/train.py \
      /solution/finetune.py /solution/predict.py /app/
chmod +x /app/split.py /app/train.py /app/finetune.py /app/predict.py
python3 -c "import ast;[ast.parse(open(p).read()) for p in ['/app/split.py','/app/train.py','/app/finetune.py','/app/predict.py']]"

# ---- 2. deterministic split -> /app/split_{train,val,test}.csv --------------
python3 /app/split.py /app/data/dataset.csv /app/split

# ---- 3. train -> /app/model_snapshot.pt --------------------------------------
python3 /app/train.py /app/split_train.csv /app/split_val.csv /app/model_snapshot.pt

# ---- 4. fine-tune a demo fold (reusable-script proof) -------------------------
python3 /app/finetune.py /app/data/finetune_fold.csv /app/finetune_snapshot.pt

# ---- 5. single-label predictions -> /app/pred_labels.txt ----------------------
python3 /app/predict.py /app/data/unlabeled.csv /app/pred_labels.txt

# ---- 6. streaming big-bag scores -> /app/large_bag_scores.txt ------------------
python3 /app/predict.py --bag /app/data/big_bag.csv /app/large_bag_scores.txt

echo "umber-vault solution done"
exit 0