#!/bin/bash
# Verifier for moss-kernel: runs the deliverable self-check, then re-invokes
# gated_ops.gated_shift_rms on hidden (N, D, seed, eps) cases against an
# independent torch reference, with shape/dtype/contiguity, determinism and
# real-Triton-source checks. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
export TRITON_INTERPRET=1
reward=0

python3 -u - <<'PY'
import importlib.util, json, os, subprocess, sys

import torch

failures = []


def log(*a):
    print("[verifier]", *a)


# ---------------- independent torch reference ----------------
def reference(a, b, g, w, eps):
    gate = torch.tanh(g).unsqueeze(1)
    h = gate * a + (1.0 - gate) * b + 1.0
    msq = h.pow(2).mean(dim=1, keepdim=True)
    scale = torch.rsqrt(msq + eps)
    return h * w.unsqueeze(0) * scale


# ---------------- import the agent's module ----------------
if not os.path.isfile("/app/gated_ops.py"):
    failures.append("missing /app/gated_ops.py")
    print("verify failures:", failures)
    sys.exit(1)

try:
    src = open("/app/gated_ops.py").read()
    if "@triton.jit" not in src:
        failures.append("gated_ops.py: no @triton.jit kernel")
    if "import triton" not in src:
        failures.append("gated_ops.py: does not import triton")
    # crude check: the jit kernel body must not call into torch
    if "@triton.jit" in src:
        body = src.split("@triton.jit", 1)[1].split("\ndef ", 1)[0]
        if "torch." in body:
            failures.append("gated_ops.py: kernel body calls into torch")
except Exception as e:
    failures.append("gated_ops.py unreadable: %r" % e)

try:
    spec = importlib.util.spec_from_file_location("agent_gated_ops", "/app/gated_ops.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
except Exception as e:
    failures.append("gated_ops.py: cannot import: %r" % e)
    print("verify failures:", failures)
    sys.exit(1)

fn = getattr(mod, "gated_shift_rms", None)
if not callable(fn):
    failures.append("missing callable gated_shift_rms")
    print("verify failures:", failures)
    sys.exit(1)


def run_case(N, D, seed, eps, label):
    torch.manual_seed(seed)
    a = torch.randn(N, D, dtype=torch.float32)
    b = torch.randn(N, D, dtype=torch.float32)
    g = torch.randn(N, dtype=torch.float32)
    w = torch.randn(D, dtype=torch.float32)
    try:
        out = fn(a, b, g, w, eps=eps)
    except Exception as e:
        failures.append("%s: call raised %r" % (label, e))
        return
    try:
        if out.shape != (N, D):
            failures.append("%s: shape %s != (%d,%d)" % (label, tuple(out.shape), N, D))
            return
        if out.dtype != torch.float32:
            failures.append("%s: dtype %s != float32" % (label, out.dtype))
            return
        if not out.is_contiguous():
            failures.append("%s: output not contiguous" % label)
        want = reference(a, b, g, w, eps)
        if not torch.allclose(out, want, atol=1e-4, rtol=1e-4):
            dev = (out - want).abs().max().item()
            failures.append("%s: numerics diverge (max abs diff %.3e)" % (label, dev))
        out2 = fn(a, b, g, w, eps=eps)
        if not torch.equal(out, out2):
            failures.append("%s: non-deterministic across calls" % label)
    except Exception as e:
        failures.append("%s: check crashed %r" % (label, e))


# shape-mismatch validation must raise, not corrupt
try:
    fn(torch.randn(2, 3), torch.randn(2, 4), torch.randn(2), torch.randn(3))
    failures.append("shape mismatch did not raise ValueError")
except ValueError:
    pass
except Exception as e:
    failures.append("shape mismatch raised %r instead of ValueError" % e)

# ---------------- hidden cases ----------------
hidden = "/tests/hidden"
cases = sorted(f for f in os.listdir(hidden) if f.endswith(".json")) if os.path.isdir(hidden) else []
if not cases:
    failures.append("no hidden cases present")
for c in cases:
    try:
        with open(os.path.join(hidden, c)) as fh:
            p = json.load(fh)
        run_case(int(p["N"]), int(p["D"]), int(p["seed"]), float(p["eps"]), "hidden %s" % c)
    except Exception as e:
        failures.append("hidden %s: bad fixture/read error %r" % (c, e))

# ---------------- deliverable self-check must pass ----------------
try:
    r = subprocess.run([sys.executable, "-u", "/app/selfcheck.py"],
                       capture_output=True, text=True, timeout=240)
    if r.returncode != 0:
        failures.append("selfcheck.py exited %s" % r.returncode)
        log("selfcheck tail:", r.stdout[-500:], r.stderr[-500:])
except Exception as e:
    failures.append("selfcheck.py run crashed: %r" % e)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
