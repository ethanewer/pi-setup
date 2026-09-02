#!/bin/bash
# Real oracle for brass-lantern: write the adapter-config generator, then RUN
# it on the visible card to produce /app/adapter_config.json. Never reads /tests.
set -eu

SOLVER="/app/make_adapter.py"
OUT="/app/adapter_config.json"

cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""Derive a PEFT-style LoRA adapter config from a model card."""
import argparse
import json
from pathlib import Path

TARGETABLE = {"Linear", "Conv1D"}


def build_config(card, rank=None, alpha=None):
    targets, to_save = [], []
    for mod in card.get("modules", []):
        if not mod.get("trainable", True):
            continue
        if mod.get("head", False):
            to_save.append(mod["name"])
        elif mod.get("type") in TARGETABLE:
            targets.append(mod["name"])
    return {
        "r": int(card["lora"]["r"]) if rank is None else int(rank),
        "lora_alpha": int(card["lora"]["lora_alpha"]) if alpha is None else int(alpha),
        "lora_dropout": card["lora"]["lora_dropout"],
        "target_modules": sorted(targets),
        "modules_to_save": sorted(to_save),
        "bias": "none",
        "task_type": "CAUSAL_LM",
        "base_model_name_or_path": card["model_name"],
        "inference_mode": True,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("card")
    ap.add_argument("out")
    ap.add_argument("--rank", type=int, default=None)
    ap.add_argument("--alpha", type=int, default=None)
    args = ap.parse_args()
    card = json.loads(Path(args.card).read_text(encoding="utf-8"))
    config = build_config(card, args.rank, args.alpha)
    Path(args.out).write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

python3 "$SOLVER" /app/model_card.json "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
cat "$OUT"
