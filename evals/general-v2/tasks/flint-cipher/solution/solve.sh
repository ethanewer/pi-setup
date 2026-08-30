#!/usr/bin/env bash
# Oracle: perform the REAL work and produce every deliverable in /app.
set -euo pipefail
cd /app
B=/solution

echo "== 1. build filtered vocabulary =="
python3 "$B/build_vocab.py" --corpus /app/data/corpus.txt \
    --out /app/vocab.txt --min-count 2

echo "== 2. train bounded BPE tokenizer =="
mkdir -p /app/tokenizer
python3 "$B/build_tokenizer.py" --corpus /app/data/corpus.txt \
    --out /app/tokenizer/bpe.model --vocab-size 512 --min-frequency 1

echo "== 3. train & evaluate tiny multilingual classifier =="
python3 "$B/train.py" --train /app/data/train.tsv \
    --dev /app/data/dev.tsv \
    --snapshot /app/classifier_snapshot.npz \
    --metrics /app/eval_metrics.json

# expose the reusable classifier + builder scripts as deliverables
cp "$B/build_vocab.py"  /app/build_vocab.py
cp "$B/build_tokenizer.py" /app/build_tokenizer.py
cp "$B/predict.py"       /app/predict.py
cp "$B/train.py"         /app/train.py
chmod +x /app/build_vocab.py /app/build_tokenizer.py /app/predict.py /app/train.py

echo "== done =="
ls -la /app