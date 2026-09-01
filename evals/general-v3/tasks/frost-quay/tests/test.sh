#!/bin/bash
# Verifier for frost-quay. Executes the deliverable export program on the
# visible checkpoint and on hidden checkpoints constructed with the pinned
# toolchain, compares reports against independently computed references, and
# enforces that the pinned torch/transformers toolchain is bit-for-bit
# preserved. Writes 0/1 to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import importlib.metadata as md
import json
import os
import subprocess
import sys

os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["TRANSFORMERS_OFFLINE"] = "1"

SOLVE = "/app/export.py"
VISIBLE_DIR = "/app/model_repo"
VISIBLE_REPORT = "/app/export_report.json"
PINS = "/app/toolchain_pins.json"
HIDDEN_MANIFEST = "/tests/hidden/manifest.json"

failures = []


# ---------- pinned toolchain preservation (competency C-d2b6ec24) ----------
def pins_intact():
    # 1. installed distribution metadata matches the hard platform baseline
    try:
        torch_d = md.version("torch")
        tr_d = md.version("transformers")
    except Exception as exc:
        failures.append("toolchain distributions missing: %r" % (exc,))
        return
    if torch_d.split("+")[0] != "2.13.0":
        failures.append("torch distribution drifted: %s" % torch_d)
    if tr_d != "5.16.1":
        failures.append("transformers distribution drifted: %s" % tr_d)
    # 2. pristine baseline manifest untouched and consistent with installs
    try:
        with open(PINS) as fh:
            pins = json.load(fh)
    except Exception as exc:
        failures.append("toolchain_pins.json missing/unreadable: %r" % (exc,))
        return
    if not isinstance(pins, dict) or set(pins) != {"torch", "transformers"}:
        failures.append("toolchain_pins.json malformed")
        return
    try:  # torch is only importable if not uninstalled/clobbered
        import torch
        import transformers
    except Exception as exc:
        failures.append("pinned toolchain not importable: %r" % (exc,))
        return
    if torch.__version__ != pins["torch"]:
        failures.append("torch runtime %s != baseline %s"
                        % (torch.__version__, pins["torch"]))
    if transformers.__version__ != pins["transformers"]:
        failures.append("transformers runtime %s != baseline %s"
                        % (transformers.__version__, pins["transformers"]))
    # 3. the checkpoint directory shipped in the image is intact
    try:
        with open(os.path.join(VISIBLE_DIR, "config.json")) as fh:
            cfg = json.load(fh)
        if (int(cfg["hidden_size"]) != 16 or int(cfg["vocab_size"]) != 64
                or int(cfg["num_hidden_layers"]) != 1):
            failures.append("visible model_repo config was altered")
    except Exception:
        failures.append("visible model_repo unreadable/modified")


# ---------- independent reference computation with the pinned stack ----------
def reference(model_dir):
    import torch
    import transformers
    from transformers import AutoModel

    model = AutoModel.from_pretrained(model_dir)
    model.eval()
    vocab = int(model.config.vocab_size)
    input_ids = torch.tensor([list(range(min(8, vocab)))], dtype=torch.long)
    attention_mask = torch.ones_like(input_ids)
    import torch as _t
    with _t.no_grad():
        out = model(input_ids=input_ids, attention_mask=attention_mask)
    return {
        "model_dir": model_dir,
        "torch_version": torch.__version__,
        "transformers_version": transformers.__version__,
        "hidden_size": int(model.config.hidden_size),
        "num_parameters": int(sum(p.numel() for p in model.parameters())),
        "last_hidden_checksum": float(out.last_hidden_state.sum()),
    }


def run_export(model_dir, out_path):
    if os.path.exists(out_path):
        os.remove(out_path)
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, model_dir, out_path],
            capture_output=True, text=True, timeout=120,
        )
    except subprocess.TimeoutExpired:
        return None, "export timed out"
    if r.returncode != 0:
        return None, "export exited %d: %s" % (r.returncode, r.stderr[-300:])
    try:
        with open(out_path) as fh:
            return json.load(fh), None
    except Exception as exc:
        return None, "output unreadable: %r" % (exc,)


def compare(got, want, label):
    if not isinstance(got, dict):
        failures.append("%s: report is not a JSON object" % label)
        return
    keys = {"model_dir", "torch_version", "transformers_version",
            "hidden_size", "num_parameters", "last_hidden_checksum"}
    if set(got.keys()) != keys:
        failures.append("%s: key set mismatch: %s" % (label, sorted(got)))
        return
    if got["model_dir"] != want["model_dir"]:
        failures.append("%s: model_dir mismatch" % label)
    if got["torch_version"] != want["torch_version"]:
        failures.append("%s: torch_version mismatch" % label)
    if got["transformers_version"] != want["transformers_version"]:
        failures.append("%s: transformers_version mismatch" % label)
    for k in ("hidden_size", "num_parameters"):
        if got[k] != want[k]:
            failures.append("%s: %s mismatch (%r != %r)"
                            % (label, k, got[k], want[k]))
    try:
        if abs(float(got["last_hidden_checksum"])
               - want["last_hidden_checksum"]) > 1e-2:
            failures.append("%s: last_hidden_checksum mismatch" % label)
    except Exception:
        failures.append("%s: last_hidden_checksum not numeric" % label)


# ---------- run everything ----------
pins_intact()

if not os.path.isfile(SOLVE):
    failures.append("missing /app/export.py")
else:
    ref = reference(VISIBLE_DIR)
    got, err = run_export(VISIBLE_DIR, "/tmp/frost_quay_vis.json")
    if err:
        failures.append("visible export: %s" % err)
    else:
        compare(got, ref, "visible")
        # visible-case deliverable report must match too
        try:
            with open(VISIBLE_REPORT) as fh:
                rep = json.load(fh)
            compare(rep, ref, "visible /app/export_report.json")
        except Exception as exc:
            failures.append("/app/export_report.json unreadable: %r" % (exc,))

    # hidden checkpoints, built with the pinned toolchain at verify time
    try:
        with open(HIDDEN_MANIFEST) as fh:
            manifest = json.load(fh)
    except Exception as exc:
        failures.append("hidden manifest unreadable: %r" % (exc,))
        manifest = {"cases": []}
    import torch
    from transformers import BertConfig, BertModel
    for case in manifest.get("cases", []):
        name = case.get("name", "?")
        try:
            cfg = BertConfig(
                vocab_size=int(case["vocab_size"]),
                hidden_size=int(case["hidden_size"]),
                num_hidden_layers=int(case["num_hidden_layers"]),
                num_attention_heads=int(case["num_attention_heads"]),
                intermediate_size=int(case["intermediate_size"]),
            )
            torch.manual_seed(int(case["seed"]))
            BertModel(cfg).save_pretrained("/tmp/frost_quay_" + name)
        except Exception as exc:
            failures.append("hidden %s: could not build checkpoint: %r"
                            % (name, exc))
            continue
        hdir = "/tmp/frost_quay_" + name
        ref = reference(hdir)
        got, err = run_export(hdir, "/tmp/frost_quay_%s.json" % name)
        if err:
            failures.append("hidden %s: %s" % (name, err))
        else:
            compare(got, ref, "hidden %s" % name)

if not manifest.get("cases"):
    failures.append("no hidden cases ran")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
