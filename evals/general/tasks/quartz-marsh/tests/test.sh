#!/bin/bash
# Verifier for quartz-marsh: ENFORCES the no-modify rule on /app/config.json,
# checks the visible deliverables, and RE-RUNS /app/init_model.py on every
# hidden config in /tests/hidden, independently re-loading and re-counting the
# saved state dict. Writes REWARD (0/1) to /logs/verifier/reward.txt. Never
# crashes on malformed agent output.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixture (the instruction forbids
# modifying it; tampering would defeat the visible-case check).
PRISTINE_CONFIG_SHA="fb7d058d9827deee8308c2225e70be546eda7a80c1510483f307f8b346506f3c"
export PRISTINE_CONFIG_SHA

python3 - <<'PY'
import hashlib, json, os, subprocess, sys

import torch

SOLVE = "/app/init_model.py"
failures = []


def fail(msg):
    failures.append(msg)


def check_run(cfg_path, must_files=None):
    """Run the program on cfg_path into temp paths and fully validate."""
    tmp_model = "/tmp/qm_check_model.pt"
    tmp_report = "/tmp/qm_check_report.json"
    for p in (tmp_model, tmp_report):
        if os.path.exists(p):
            os.remove(p)
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, "--config", cfg_path,
             "--model-out", tmp_model, "--report-out", tmp_report],
            capture_output=True, text=True, timeout=240,
        )
    except Exception as e:
        fail("run crashed on %s: %r" % (cfg_path, e))
        return
    if r.returncode != 0:
        fail("program exited %d on %s: %s" % (r.returncode, cfg_path, r.stderr[-300:]))
        return
    if not os.path.isfile(tmp_model) or not os.path.isfile(tmp_report):
        fail("missing outputs for %s" % cfg_path)
        return
    validate_state_and_report(tmp_model, tmp_report, cfg_path)
    # If the agent was asked to produce default-path artifacts for this config
    # (the visible case), validate those too.
    if must_files:
        m, rep = must_files
        if not (os.path.isfile(m) and os.path.isfile(rep)):
            fail("missing default deliverables %s / %s" % (m, rep))
        else:
            validate_state_and_report(m, rep, cfg_path)


def validate_state_and_report(model_path, report_path, cfg_path):
    try:
        with open(cfg_path) as fh:
            cfg = json.load(fh)
    except Exception as e:
        fail("unreadable config %s: %r" % (cfg_path, e))
        return
    f, c = int(cfg["feature_dim"]), int(cfg["num_classes"])
    lo, hi = int(cfg["min_params"]), int(cfg["max_params"])

    try:
        state = torch.load(model_path, map_location="cpu", weights_only=True)
    except Exception as e:
        fail("model %s not loadable: %r" % (model_path, e))
        return
    if not isinstance(state, dict):
        fail("model is not a state dict")
        return
    expected_keys = {
        "instance_encoder.weight", "instance_encoder.bias",
        "bag_classifier.weight", "bag_classifier.bias",
    }
    if set(state.keys()) != expected_keys:
        fail("state dict keys %s != %s" % (sorted(state.keys()), sorted(expected_keys)))
        return
    for k, t in state.items():
        if t is None:
            fail("component tensor %s is None" % k)
            return
        if t.dtype not in (torch.float32, torch.float64):
            fail("tensor %s has non-float dtype %s" % (k, t.dtype))
            return
        if not torch.isfinite(t).all().item():
            fail("tensor %s has non-finite values" % k)
            return

    ew = state["instance_encoder.weight"]
    eb = state["instance_encoder.bias"]
    cw = state["bag_classifier.weight"]
    cb = state["bag_classifier.bias"]
    if list(ew.shape) != [ew.shape[0], f]:
        fail("instance_encoder.weight %s does not match feature_dim %d" % (list(ew.shape), f))
        return
    h = int(ew.shape[0])
    if list(eb.shape) != [h]:
        fail("instance_encoder.bias %s inconsistent with hidden %d" % (list(eb.shape), h))
        return
    if list(cw.shape) != [c, h]:
        fail("bag_classifier.weight %s != [%d, %d]" % (list(cw.shape), c, h))
        return
    if list(cb.shape) != [c]:
        fail("bag_classifier.bias %s != [%d]" % (list(cb.shape), c))
        return

    param_count = sum(int(t.numel()) for t in state.values())
    if not (lo <= param_count <= hi):
        fail("param_count %d outside [%d, %d]" % (param_count, lo, hi))
        return

    try:
        with open(report_path) as fh:
            rep = json.load(fh)
    except Exception as e:
        fail("unreadable report %s: %r" % (report_path, e))
        return
    if not isinstance(rep, dict):
        fail("report is not a dict")
        return
    want = {
        "feature_dim": f,
        "num_classes": c,
        "hidden_dim": h,
        "param_count": param_count,
        "min_params": lo,
        "max_params": hi,
        "init_ok": True,
        "within_budget": True,
    }
    if set(rep.keys()) != set(want.keys()):
        fail("report keys %s != %s" % (sorted(rep.keys()), sorted(want.keys())))
        return
    for k, v in want.items():
        if rep[k] != v:
            fail("report field %s = %r, expected %r" % (k, rep[k], v))


# no-modify check on the visible config
pristine = os.environ.get("PRISTINE_CONFIG_SHA", "")
try:
    actual = hashlib.sha256(open("/app/config.json", "rb").read()).hexdigest()
except Exception:
    actual = None
if actual != pristine:
    fail("visible config modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    fail("missing /app/init_model.py")
else:
    # visible case: validate the default-path deliverables AND re-run
    if os.path.isfile("/app/config.json"):
        check_run("/app/config.json",
                  must_files=("/app/model_pack.pt", "/app/init_report.json"))
    else:
        fail("visible config missing")

    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            fail("no hidden cases present")
        for cname in cases:
            cfg = os.path.join(hidden_dir, cname, "config.json")
            if not os.path.isfile(cfg):
                fail("hidden case '%s' malformed" % cname)
                continue
            check_run(cfg)
    else:
        fail("no hidden cases dir")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
