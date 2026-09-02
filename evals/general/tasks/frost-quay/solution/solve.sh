#!/bin/bash
# Oracle for frost-quay: authors the deliverable export program, then RUNS it
# on the visible checkpoint to produce /app/export_report.json. Never reads
# /tests; never touches the pinned toolchain.
set -eu

EXPORTER="/app/export.py"
REPORT="/app/export_report.json"

cat > "$EXPORTER" <<'PY'
#!/usr/bin/env python3
"""Offline encoder export bench (frost-quay).

Loads a local HF-format encoder checkpoint with the pinned platform
toolchain, pushes the fixed probe sequence through it, and writes the export
report. Fully offline: hub access is disabled before transformers is imported.
"""
import os
import sys

# Force offline mode BEFORE transformers is imported (bench contract).
os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["TRANSFORMERS_OFFLINE"] = "1"

import json

import torch
import transformers
from transformers import AutoModel


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: export.py <model_dir> <output_json>", file=sys.stderr)
        return 2
    model_dir, out_path = sys.argv[1], sys.argv[2]

    model = AutoModel.from_pretrained(model_dir)
    model.eval()

    vocab = int(model.config.vocab_size)
    ids = list(range(min(8, vocab)))
    input_ids = torch.tensor([ids], dtype=torch.long)
    attention_mask = torch.ones_like(input_ids)

    with torch.no_grad():
        outputs = model(input_ids=input_ids, attention_mask=attention_mask)
    last_hidden = outputs.last_hidden_state

    report = {
        "model_dir": model_dir,
        "torch_version": torch.__version__,
        "transformers_version": transformers.__version__,
        "hidden_size": int(model.config.hidden_size),
        "num_parameters": int(sum(p.numel() for p in model.parameters())),
        "last_hidden_checksum": round(float(last_hidden.sum()), 6),
    }
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2, sort_keys=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY

chmod +x "$EXPORTER"

# Run the real work against the visible checkpoint.
python3 "$EXPORTER" /app/model_repo "$REPORT"

echo "solve.sh done -> $EXPORTER and $REPORT"
cat "$REPORT"
