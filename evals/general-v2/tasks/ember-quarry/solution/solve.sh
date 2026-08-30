#!/bin/bash
# Oracle for ember-quarry: write the deliverable program /app/mil.py, then RUN
# it on the visible fixture to produce /app/report.json. Never reads /tests.
set -eu

SOLVER="/app/mil.py"
OUT="/app/report.json"

cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""MIL bag classifier forward pass (ember-quarry)."""
import argparse
import json

import numpy as np
import torch


class MILClassifier(torch.nn.Module):
    """Attention-gated multiple-instance-learning classifier."""

    def __init__(self, in_dim: int, hidden: int, num_classes: int):
        super().__init__()
        self.encoder = torch.nn.Linear(in_dim, hidden)
        self.gate = torch.nn.Linear(hidden, 1)
        self.classifier = torch.nn.Linear(hidden, num_classes)

    def embed(self, x: torch.Tensor) -> torch.Tensor:
        return torch.relu(self.encoder(x))

    def attention(self, x: torch.Tensor) -> torch.Tensor:
        emb = self.embed(x)
        if emb.shape[0] == 0:
            return torch.zeros(0, 1)
        return torch.softmax(self.gate(emb), dim=0)

    def forward(self, x: torch.Tensor):
        attention = self.attention(x)
        if x.shape[0] == 0:
            logits = torch.zeros(self.classifier.out_features)
        else:
            logits = self.classifier((self.embed(x) * attention).sum(dim=0))
        return logits, attention


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True)
    ap.add_argument("--bag", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    with open(args.config) as fh:
        cfg = json.load(fh)
    torch.manual_seed(cfg["seed"])
    model = MILClassifier(cfg["in_dim"], cfg["hidden"], cfg["num_classes"])
    model.eval()

    with np.load(args.bag) as data:
        X = np.asarray(data["X"], dtype=np.float32)
    x = torch.from_numpy(X)

    with torch.no_grad():
        logits, attention = model(x)

    report = {
        "logits": [float(v) for v in logits],
        "attention": [float(v) for v in attention.reshape(-1)],
        "instance_count": int(X.shape[0]),
        "pred_class": int(torch.argmax(logits).item()),
    }
    with open(args.out, "w") as fh:
        json.dump(report, fh, indent=2)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY

chmod +x "$SOLVER"

# Produce the visible-case deliverable by executing the program (not canned).
python3 "$SOLVER" --config /app/config.json --bag /app/input/bag.npz --out "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
