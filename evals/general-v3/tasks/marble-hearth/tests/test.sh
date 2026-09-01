#!/bin/bash
# Verifier for marble-hearth: checks the three deliverables, that the pinned
# torch/transformers toolchain survived bit-for-bit after the agent's installer
# ran, that hearthrt/attrs/six are installed at the pinned versions, and
# EXECUTES /app/infer.py on the visible batch and on every hidden case fully
# offline. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
export HF_HUB_OFFLINE=1
export TRANSFORMERS_OFFLINE=1

ok=1
fail() { echo "FAIL: $*" >&2; ok=0; }

# ---------- deliverables present ----------
[ -f /app/install_extras.sh ] || fail "missing /app/install_extras.sh"
[ -x /app/install_extras.sh ] || fail "/app/install_extras.sh is not executable"
[ -f /app/infer.py ]          || fail "missing /app/infer.py"
[ -f /app/batch_output.json ] || fail "missing /app/batch_output.json"

# ---------- pinned toolchain + extras state ----------
python3 - <<'PY' || fail "toolchain/extras state check failed"
import importlib.metadata as md
import sys

failures = []

def need(dist, ver):
    try:
        got = md.version(dist)
    except Exception as exc:
        failures.append(f"{dist}: not installed ({exc})")
        return
    if got != ver:
        failures.append(f"{dist}: version {got} != pinned {ver}")

# extras installed by the agent's installer
need("attrs", "25.3.0")
need("six", "1.17.0")

# pinned platform toolchain must be intact bit-for-bit
need("torch", "2.13.0")
need("transformers", "5.16.1")

import torch
import transformers
if torch.__version__ != "2.13.0+cu130":
    failures.append(f"torch.__version__ {torch.__version__} != 2.13.0+cu130")
if transformers.__version__ != "5.16.1":
    failures.append(f"transformers.__version__ {transformers.__version__} != 5.16.1")

# hearthrt installed system-wide with the appliance id
try:
    import hearthrt
    assert hearthrt.APPLIANCE_ID == "hearth-mini-9f41c2", hearthrt.APPLIANCE_ID
except Exception as exc:
    failures.append(f"hearthrt import/APPLIANCE_ID: {exc}")

if failures:
    for f in failures:
        print("STATE-FAIL:", f, file=sys.stderr)
    sys.exit(1)
PY

# ---------- offline load path sanity through the pinned toolchain ----------
python3 - <<'PY' || fail "offline load of /app/model_store/hearth-mini failed"
from transformers import AutoModelForCausalLM, AutoTokenizer
tok = AutoTokenizer.from_pretrained("/app/model_store/hearth-mini", local_files_only=True)
model = AutoModelForCausalLM.from_pretrained("/app/model_store/hearth-mini", local_files_only=True)
assert model.config.vocab_size == tok.vocab_size
PY

# ---------- execute /app/infer.py and compare ----------
python3 - <<'PY'
import json
import os
import subprocess
import sys

INFER = "/app/infer.py"
failures = []


def canon(path):
    with open(path) as fh:
        obj = json.load(fh)
    assert isinstance(obj, dict), "top level must be an object"
    assert set(obj.keys()) == {"appliance_id", "results"}, sorted(obj.keys())
    assert obj["appliance_id"] == "hearth-mini-9f41c2", obj["appliance_id"]
    results = obj["results"]
    assert isinstance(results, list)
    out = []
    for r in results:
        assert isinstance(r, dict) and set(r.keys()) == {"prompt", "next_token_id", "next_token"}, r
        assert isinstance(r["prompt"], str)
        assert isinstance(r["next_token_id"], int) and not isinstance(r["next_token_id"], bool)
        assert isinstance(r["next_token"], str)
        out.append((r["prompt"], r["next_token_id"], r["next_token"]))
    return out


def run_case(model_dir, prompts, expected_path):
    out = "/tmp/marble_hearth_out.json"
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run(
            [sys.executable, INFER, model_dir, prompts, out],
            capture_output=True, text=True, timeout=180,
        )
    except subprocess.TimeoutExpired:
        failures.append("infer.py timed out")
        return
    if r.returncode != 0:
        failures.append(f"infer.py exited {r.returncode}: {r.stderr[-400:]}")
        return
    try:
        got = canon(out)
        want = canon(expected_path)
    except Exception as exc:
        failures.append(f"unreadable/invalid output ({exc})")
        return
    if got != want:
        failures.append(f"output mismatch for {model_dir} + {prompts}")


# visible case (re-executed) + visible deliverable file
if os.path.isfile("/app/infer.py"):
    if not all(os.path.exists(p) for p in
               ("/app/model_store/hearth-mini", "/app/prompts.txt", "/tests/expected_visible.json")):
        failures.append("visible inputs/expected missing")
    else:
        run_case("/app/model_store/hearth-mini", "/app/prompts.txt", "/tests/expected_visible.json")
        try:
            if canon("/app/batch_output.json") != canon("/tests/expected_visible.json"):
                failures.append("/app/batch_output.json does not match visible expected")
        except Exception as exc:
            failures.append(f"/app/batch_output.json unreadable ({exc})")

    # hidden cases
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            model = os.path.join(base, "model")
            prompts = os.path.join(base, "prompts.txt")
            exp = os.path.join(base, "expected.json")
            if not (os.path.isdir(model) and os.path.isfile(prompts) and os.path.isfile(exp)):
                failures.append(f"hidden case '{c}' malformed")
                continue
            run_case(model, prompts, exp)
    else:
        failures.append("no hidden case dir")

for f in failures:
    print("VERIFY-FAIL:", f, file=sys.stderr)
sys.exit(1 if failures else 0)
PY

[ $? -eq 0 ] || ok=0

echo "$ok" > /logs/verifier/reward.txt
exit 0
