#!/bin/bash
# Oracle for glass-mantle: write the deliverable module /app/setpool.py, then
# RUN its CLI on the visible fixture to produce /app/pooled.json, and sanity
# import it. Never reads /tests.
set -eu

MOD="/app/setpool.py"
OUT="/app/pooled.json"

cat > "$MOD" <<'PY'
"""GatedSetPooling: attention-gated set pooling (glass-mantle)."""
import argparse
import json

import numpy as np
import torch


class GatedSetPooling(torch.nn.Module):
    """Attention gate over a set of feature rows plus an aggregation head."""

    def __init__(self, in_dim: int, attn_dim: int, out_dim: int):
        super().__init__()
        self.proj = torch.nn.Linear(in_dim, attn_dim)
        self.score = torch.nn.Linear(attn_dim, 1)
        self.head = torch.nn.Linear(in_dim, out_dim)

    def attention(self, x: torch.Tensor) -> torch.Tensor:
        logits = self.score(torch.tanh(self.proj(x)))
        if x.dim() == 2:
            if x.shape[0] == 0:
                return torch.zeros(0, 1)
            return torch.softmax(logits, dim=0)
        if x.dim() == 3:
            if x.shape[1] == 0:
                return torch.zeros(x.shape[0], 0, 1)
            return torch.softmax(logits, dim=1)
        raise ValueError("x must be rank-2 or rank-3, got dim=%d" % x.dim())

    def forward(self, x: torch.Tensor):
        weights = self.attention(x)
        if x.dim() == 2:
            if x.shape[0] == 0:
                pooled = self.head(torch.zeros(x.shape[1]))
            else:
                pooled = self.head((x * weights).sum(dim=0))
        else:
            if x.dim() == 3 and x.shape[1] == 0:
                pooled = self.head(torch.zeros(x.shape[0], x.shape[2]))
            else:
                pooled = self.head((x * weights).sum(dim=1))
        return pooled, weights


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True)
    ap.add_argument("--clusters", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    with open(args.config) as fh:
        cfg = json.load(fh)
    torch.manual_seed(cfg["seed"])
    model = GatedSetPooling(cfg["in_dim"], cfg["attn_dim"], cfg["out_dim"])
    model.eval()

    with np.load(args.clusters) as data:
        X = np.asarray(data["X"], dtype=np.float32)
    x = torch.from_numpy(X)

    with torch.no_grad():
        pooled, weights = model(x)

    report = {
        "pooled": [float(v) for v in pooled.reshape(-1)],
        "weights": [float(v) for v in weights.reshape(-1)],
        "bag": int(X.shape[0]),
    }
    with open(args.out, "w") as fh:
        json.dump(report, fh, indent=2)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY

chmod +x "$MOD"

# Sanity import, then produce the visible deliverable by executing the CLI.
python3 -c "import importlib.util; s=importlib.util.spec_from_file_location('setpool','/app/setpool.py'); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); assert hasattr(m,'GatedSetPooling')"
python3 "$MOD" --config /app/config.json --clusters /app/clusters.npz --out "$OUT"

echo "solve.sh done -> $MOD and $OUT"
ls -l "$MOD" "$OUT"
