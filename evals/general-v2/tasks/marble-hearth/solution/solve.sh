#!/bin/bash
# Oracle for marble-hearth: authors the two deliverable scripts, runs the
# installer, then runs the inference CLI on the visible batch to produce
# /app/batch_output.json. Never reads /tests.
set -eu

# ---- 1. /app/install_extras.sh -------------------------------------------
cat > /app/install_extras.sh <<'SH'
#!/bin/bash
# Idempotent installer for the marble-hearth appliance extras.
# NEVER touches the pinned torch/transformers toolchain.
set -eu

if ! python3 -c "import importlib.metadata as md, sys; sys.exit(0 if md.version('attrs') == '25.3.0' else 1)" 2>/dev/null; then
    pip install --no-cache-dir --disable-pip-version-check attrs==25.3.0
fi

if ! python3 -c "import importlib.metadata as md, sys; sys.exit(0 if md.version('six') == '1.17.0' else 1)" 2>/dev/null; then
    pip install --no-cache-dir --disable-pip-version-check six==1.17.0
fi

if ! python3 -c "import hearthrt" 2>/dev/null; then
    pip install --no-cache-dir --disable-pip-version-check \
        --no-build-isolation --no-deps /app/pkgs/hearthrt_pkg
fi

python3 -c "import attrs, six, hearthrt; print('extras ok')"
SH
chmod +x /app/install_extras.sh

# ---- 2. /app/infer.py ------------------------------------------------------
cat > /app/infer.py <<'PY'
#!/usr/bin/env python3
"""marble-hearth offline next-token scorer.

Usage: python3 /app/infer.py <model_dir> <prompts.txt> <out_json>

Loads the model store from disk (local_files_only=True, no network) and, for
each non-blank prompt line, records the argmax next-token prediction at the
last position.
"""
import json
import sys

import torch
from transformers import AutoModelForCausalLM, AutoTokenizer

import hearthrt


def main():
    model_dir, prompts_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]

    tok = AutoTokenizer.from_pretrained(model_dir, local_files_only=True)
    model = AutoModelForCausalLM.from_pretrained(model_dir, local_files_only=True)
    model.eval()

    results = []
    with open(prompts_path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n").rstrip("\r")
            if not line.strip():
                continue
            enc = tok(line, return_tensors="pt", add_special_tokens=False)
            with torch.no_grad():
                logits = model(**enc).logits[0, -1]
            nid = int(torch.argmax(logits).item())
            results.append({
                "prompt": line,
                "next_token_id": nid,
                "next_token": tok.decode([nid]),
            })

    payload = {"appliance_id": hearthrt.APPLIANCE_ID, "results": results}
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, indent=2, sort_keys=True)


if __name__ == "__main__":
    main()
PY
chmod +x /app/infer.py

# ---- 3. Run installer, then the visible batch ------------------------------
bash /app/install_extras.sh

python3 /app/infer.py /app/model_store/hearth-mini /app/prompts.txt /app/batch_output.json

echo "solve.sh done"
ls -l /app/install_extras.sh /app/infer.py /app/batch_output.json
