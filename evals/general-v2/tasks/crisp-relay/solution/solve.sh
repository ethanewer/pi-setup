#!/bin/bash
# Oracle for crisp-relay: write the vendor installer and the offline scorer,
# run the installer (never touching the pinned toolchain), then RUN the scorer
# on the visible inbox to produce /app/scores.json. Never reads /tests.
set -eu

cat > /app/install_vendor.sh <<'SH'
#!/bin/bash
# Idempotent offline install of the two vendor wheels. Deliberately does NOT
# touch the pinned torch/transformers toolchain.
set -eu
pip install --no-index --no-cache-dir --disable-pip-version-check \
    --find-links /app/wheelhouse "toksplit==0.5.2" "textnorm==1.3.0"
SH
chmod +x /app/install_vendor.sh

cat > /app/score.py <<'PY'
import json
import sys

import textnorm
import toksplit
import torch
from transformers import BertForSequenceClassification, BertTokenizer

STORE = "/app/model_store"


def main():
    if len(sys.argv) != 3:
        print("usage: score.py <input.txt> <output.json>", file=sys.stderr)
        return 2
    in_path, out_path = sys.argv[1], sys.argv[2]

    docs = []
    with open(in_path, "r", encoding="utf-8") as fh:
        for line in fh:
            if line.strip() == "":
                continue
            norm = textnorm.normalize(line)
            toks = toksplit.tokenize(norm)
            docs.append(" ".join(toks))

    tok = BertTokenizer.from_pretrained(STORE, local_files_only=True)
    model = BertForSequenceClassification.from_pretrained(
        STORE, local_files_only=True)
    model.eval()

    labels = []
    with torch.no_grad():
        for text in docs:
            enc = tok(text, truncation=True, max_length=16,
                      return_tensors="pt")
            logits = model(**enc).logits[0]
            labels.append(int(logits.argmax()))

    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump({"count": len(labels), "labels": labels}, fh)
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY
chmod +x /app/score.py

bash /app/install_vendor.sh
python3 /app/score.py /app/inbox.txt /app/scores.json

echo "solve.sh done"
ls -l /app/install_vendor.sh /app/score.py /app/scores.json
