#!/usr/bin/env bash
# Oracle for quartz-summit.
# Installs the real training harness at /app/train.py and RUNS it (CPU) so the
# deliverable /app/artifact (300-dim embeddings) is produced by doing the work.
set -euo pipefail

install -m 0755 /solution/train.py /app/train.py
python3 /app/train.py --train_path /app/corpus.txt \
    --split_path /app/heldout.txt --out /app/artifact --dim 300 \
    >/tmp/train_oracle.log 2>&1

# the trained artifact must exist and be non-trivial
[ -s /app/artifact ]
python3 - <<'EOF'
import torch
d = torch.load("/app/artifact", map_location="cpu", weights_only=False)
e = d["embed"].numpy() if hasattr(d["embed"], "numpy") else d["embed"]
assert e.ndim == 2 and e.shape[1] == 300, f"bad embed shape {e.shape}"
print(f"oracle artifact OK: {d['vocab_size']}x300")
EOF
echo "solve.sh: quartz-summit deliverable produced"
