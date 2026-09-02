#!/usr/bin/env bash
# Verifier: execute every mandated deliverable and run each hidden case, then
# write the numeric reward to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0

echo "== deliverable existence =="
for f in /app/vocab.txt /app/build_vocab.py /app/tokenizer/bpe.model \
         /app/build_tokenizer.py /app/train.py /app/predict.py \
         /app/classifier_snapshot.npz /app/eval_metrics.json; do
  if [ -e "$f" ]; then
    echo "  OK  $f"
  else
    echo "MISSING $f"; echo "$reward" > /logs/verifier/reward.txt; exit 1
  fi
done

echo "== shipped vocab sanity =="
python3 - <<'PY'
import sys
sys.path.insert(0, "/tests")
from check_terms import REQUIRED_TERMS
try:
    s = set(open("/app/vocab.txt").read().split())
except Exception as e:
    print("FAIL shipped vocab unreadable", e); sys.exit(1)
if not set(REQUIRED_TERMS) <= s:
    print("FAIL shipped vocab missing", sorted(set(REQUIRED_TERMS) - s)); sys.exit(1)
print("PASS shipped vocab holds 25 required terms")
PY
[ $? -eq 0 ] || { echo "$reward" > /logs/verifier/reward.txt; exit 1; }

echo "== hidden vocab =="
python3 /tests/check_vocab.py      || { echo "$reward" > /logs/verifier/reward.txt; exit 1; }
echo "== hidden bpe =="
python3 /tests/check_tokenizer.py  || { echo "$reward" > /logs/verifier/reward.txt; exit 1; }
echo "== hidden classifier =="
python3 /tests/check_classifier.py || { echo "$reward" > /logs/verifier/reward.txt; exit 1; }

reward=1
echo "$reward" > /logs/verifier/reward.txt
echo "VERIFIER RESULT: REWARD=1"
exit 0