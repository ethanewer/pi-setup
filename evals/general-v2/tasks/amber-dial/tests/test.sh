#!/bin/bash
# Verifier for tasks/amber-dial (executes-deliverable).
#
# Re-invokes the deliverable /app/solve.py and independently checks each
# competency gate:
#   * the two-head policy/WDL forward engine (policy_logits + post-softmax value),
#   * the row- and column-parallel linear layers match a dense linear forward
#     AND produce dense-matching sharded gradients,
#   * the forward engine generalizes to fresh hidden feature inputs (valid,
#     empty, and malformed shapes),
#   * the Flask POST /classify endpoint returns the documented structured JSON
#     on normal, empty, and malformed requests.
# It then runs solve.py's --validate-parallel / --infer sub-commands over the
# hidden cases in /tests/hidden and cross-checks them independently.  Writes a
# numeric reward to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier

if [ ! -f /app/solve.py ]; then
  echo "missing deliverable /app/solve.py" >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

python3 - <<'PYEOF'
import json
import math
import os
import re
import subprocess
import sys
import time
import urllib.request
import urllib.error

import numpy as np
import torch
import torch.nn.functional as F

failures = []
HALL = "/tests/hidden"

def run(cmd, timeout=60):
    # Bounded execution: a deliverable that does not terminate promptly is a
    # legitimate failure (scored 0) rather than a whole-verifier hard timeout.
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        class _TO:
            returncode = 124
            stdout = ""
            stderr = "deliverable exceeded %ss" % timeout
        return _TO()

def read_json(path):
    with open(path) as fh:
        return json.load(fh)

# ---------------------------------------------------------------------------
# Re-run the deliverable to recreate /app/answer.json + /app/model.pt from
# scratch and confirm it is reproducible.
# ---------------------------------------------------------------------------
r = run(["python3", "/app/solve.py"])
if r.returncode != 0:
    failures.append("default run failed (rc=%d): %s"
                    % (r.returncode, (r.stderr or "")[-400:]))
if not os.path.exists("/app/answer.json"):
    failures.append("default run did not write /app/answer.json")
if not os.path.exists("/app/model.pt"):
    failures.append("default run did not write /app/model.pt")

def dense_pair(in_f, out_f, seed):
    """Independently rebuild the dense Wrow/Wcol the parallel layers must equal,
    using the documented seed + init, matching the solver's creation order."""
    torch.manual_seed(seed)
    Wrow = torch.randn(out_f, in_f) * 0.05
    Wcol = torch.randn(out_f, in_f) * 0.05
    brow = torch.zeros(out_f)
    bcol = torch.zeros(out_f)
    return Wrow, brow, Wcol, bcol

def run_validate(d):
    cmd = ["python3", "/app/solve.py", "--validate-parallel",
           "--in-features", str(d["in_features"]),
           "--out-features", str(d["out_features"]),
           "--world-size", str(d["world_size"]),
           "--seed", str(d["seed"]),
           "--batch", str(d["batch"])]
    if isinstance(d.get("input"), str):
        cmd += ["--input", d["input"] if os.path.isabs(d["input"])
                else os.path.join(HALL, "parallel_1", d["input"])]
    r = run(cmd)
    if r.returncode != 0:
        return None, "validate crashed rc=%s: %s" % (r.returncode, (r.stderr or "")[-200:])
    try:
        return json.loads(r.stdout), None
    except Exception as exc:
        return None, "validate did not print JSON: %r" % exc

# ---------------------------------------------------------------------------
# B. answer.json report cross-check.
# ---------------------------------------------------------------------------
if os.path.exists("/app/answer.json"):
    try:
        ans = read_json("/app/answer.json")
    except Exception as exc:
        ans = None
        failures.append("answer.json unreadable: %r" % exc)
    if isinstance(ans, dict):
        arch = ans.get("arch", {})
        if not (arch.get("num_moves") == 2156 and arch.get("world_size") == 8
                and arch.get("hidden") == 128 and arch.get("in_features") == 64):
            failures.append("answer.json arch fields wrong: %r" % arch)
        train = ans.get("train", {})
        for k, lo in (("policy_top1_accuracy", 0.5), ("value_top1_accuracy", 0.5)):
            v = train.get(k)
            if not (isinstance(v, (int, float)) and math.isfinite(v) and v >= lo):
                failures.append("answer.json %s below/%s: %r" % (k, lo, v))
        par = ans.get("parallel", {})
        if par.get("ok") is not True:
            failures.append("answer.json parallel.ok not true")
        for key in ("row_forward_max_abs_diff", "col_forward_max_abs_diff",
                    "row_grad_max_abs_diff", "col_grad_max_abs_diff"):
            v = par.get(key)
            if not (isinstance(v, (int, float)) and math.isfinite(v) and v < 1e-4):
                failures.append("answer.json %s not tiny: %r" % (key, v))
        if ans.get("flask_empty_label") != "neutral":
            failures.append("answer.json flask_empty_label != neutral")
else:
    failures.append("answer.json missing")

# ---------------------------------------------------------------------------
# C. Hidden: tensor-parallel layers — fresh numeric case + nondivisible edges.
# ---------------------------------------------------------------------------
def check_parallel_valid(d):
    res, err = run_validate(d)
    if err:
        failures.append("parallel valid: %s" % err)
        return
    if res.get("ok") is not True:
        failures.append("parallel valid: ok not true: %s" % res)
        return
    for key in ("row_forward_max_abs_diff", "col_forward_max_abs_diff",
                "row_grad_max_abs_diff", "col_grad_max_abs_diff"):
        if res.get(key, 1e9) >= 1e-4:
            failures.append("parallel valid: %s >= 1e-4: %r" % (key, res.get(key)))
    # Independent cross-check: rebuild the dense reference, compare to the
    # solver's reported forward row output on the hidden input tensor.
    xs = np.load(os.path.join(HALL, "parallel_1", d["input"]))
    x = torch.from_numpy(xs.astype(np.float32))
    Wrow, brow, _, _ = dense_pair(d["in_features"], d["out_features"],
                                  d["seed"])
    dense_row = F.linear(x, Wrow, brow)
    y_row = np.asarray(res["y_row"], dtype=np.float64)
    flat = dense_row.reshape(-1).detach().cpu().numpy()
    if y_row.shape != flat.shape:
        failures.append("parallel valid: y_row length %r != %r"
                        % (y_row.shape, flat.shape))
        return
    err = float(np.abs(y_row - flat).max())
    if err > 1e-4:
        failures.append("parallel valid: independent forward mismatch %.3g" % err)

def check_nondiv(path, reason):
    d = read_json(os.path.join(HALL, "parallel_1", path))
    res, err = run_validate(d)
    if err:
        failures.append("%s: %s" % (path, err)); return
    if res.get("ok") is not False:
        failures.append("%s: expected ok=False, got %s" % (path, res))
    elif res.get("reason") != reason:
        failures.append("%s: reason=%r want %r" % (path, res.get("reason"), reason))

check_parallel_valid(read_json(os.path.join(HALL, "parallel_1", "valid.json")))
check_nondiv("nondiv_input.json", "nondivisible_input")
check_nondiv("nondiv_output.json", "nondivisible_output")

# ---------------------------------------------------------------------------
# D. Hidden: engine forward generalization on fresh inputs.
# ---------------------------------------------------------------------------
def infer_features(path, expect_n=None, expect_error=None):
    out = run(["python3", "/app/solve.py", "--infer", path])
    if expect_error is not None:
        if out.returncode == 0:
            failures.append("infer %s expected non-zero rc" % path)
            try:
                res = json.loads(out.stdout)
            except Exception:
                res = {}
            if res.get("error") != expect_error:
                failures.append("infer %s error=%r want %r"
                                % (path, res.get("error"), expect_error))
        return
    if out.returncode != 0:
        failures.append("infer %s failed rc=%s: %s"
                        % (path, out.returncode, (out.stderr or "")[-200:]))
        return
    try:
        res = json.loads(out.stdout)
    except Exception as exc:
        failures.append("infer %s no JSON: %r" % (path, exc)); return
    if res.get("policy_logits_shape") != [expect_n, 2156]:
        failures.append("infer %s policy shape wrong: %r"
                        % (path, res.get("policy_logits_shape")))
    if res.get("value_shape") != [expect_n, 3]:
        failures.append("infer %s value shape wrong: %r"
                        % (path, res.get("value_shape")))
    vs = res.get("value_rowsum_max_abs_err")
    if vs is None or not math.isfinite(float(vs)) or float(vs) > 1e-3:
        failures.append("infer %s value sum not ~1: %r" % (path, vs))
    if res.get("policy_finite") is not True or res.get("all_in_unit_interval") is not True:
        failures.append("infer %s range flags: %r" % (path, res))

infer_features(os.path.join(HALL, "infer_1", "valid", "features.npy"), expect_n=20)
infer_features(os.path.join(HALL, "infer_1", "edge", "badshape.npy"),
               expect_error="bad-shape")
infer_features(os.path.join(HALL, "infer_1", "edge", "empty.npy"), expect_n=0)

# ---------------------------------------------------------------------------
# E. Flask: live POST /classify endpoint. Expected results are recomputed with
#    the same documented heuristic; malformed / missing-text / non-JSON requests
#    must be rejected with HTTP 400 + a JSON error body. Empty text is neutral.
# ---------------------------------------------------------------------------
POSITIVE_WORDS = {"good", "great", "excellent", "fast", "clean", "strong",
                  "stable", "improved", "brilliant", "liked"}
NEGATIVE_WORDS = {"bad", "worst", "poor", "slow", "broken", "fail", "late",
                  "drop", "clunky", "buggy"}
NEUTRAL_WORDS = {"okay", "fine", "average", "same", "normal", "steady"}

def classify_expected(text):
    if text is None or str(text).strip() == "":
        return {"label": "neutral",
                "confidence": {"positive": 1/3.0, "negative": 1/3.0,
                               "neutral": 1/3.0}}
    toks = re.findall(r"[a-z']+", (text or "").lower())
    pos = sum(1 for t in toks if t in POSITIVE_WORDS)
    neg = sum(1 for t in toks if t in NEGATIVE_WORDS)
    neu = sum(1 for t in toks if t in NEUTRAL_WORDS)
    if pos > neg: label = "positive"
    elif pos < neg: label = "negative"
    else: label = "neutral" if neu > 0 else "positive"
    raw = {"positive": pos + 1, "negative": neg + 1, "neutral": neu + 1}
    total = float(sum(raw.values()))
    conf = {k: round(v / total, 6) for k, v in raw.items()}
    return {"label": label, "confidence": conf}

PORT = 8735
server = subprocess.Popen(["python3", "/app/solve.py", "--serve", str(PORT)],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
flask_failures = []
try:
    ready = False
    for _ in range(60):
        try:
            urllib.request.urlopen("http://127.0.0.1:%d/" % PORT, timeout=1.0)
            ready = True
            break
        except Exception:
            time.sleep(0.3)
    if not ready:
        flask_failures.append("flask server never became ready")
    else:
        samples = read_json(os.path.join(HALL, "flask_1", "samples.json"))
        for s in samples["samples"]:
            body = json.dumps({"text": s["text"]}).encode()
            req = urllib.request.Request("http://127.0.0.1:%d/classify" % PORT,
                                         data=body,
                                         headers={"Content-Type": "application/json"})
            try:
                with urllib.request.urlopen(req, timeout=5) as resp:
                    got = json.loads(resp.read().decode())
            except Exception as exc:
                flask_failures.append("classify %r request failed: %r" % (s["text"], exc))
                continue
            exp = classify_expected(s["text"])
            if got.get("label") != exp["label"]:
                flask_failures.append("classify %r label=%r want %r"
                                      % (s["text"], got.get("label"), exp["label"]))
            gc = got.get("confidence", {})
            if sorted(gc) != ["negative", "neutral", "positive"]:
                flask_failures.append("classify %r confidence keys wrong: %r" % (s["text"], gc))
            else:
                if abs(round(sum(gc.values()), 5) - 1.0) > 1e-5:
                    flask_failures.append("classify %r confidence sum != 1: %r"
                                          % (s["text"], gc))
                disp = max(abs(gc[k] - exp["confidence"][k]) for k in gc)
                if disp > 1e-6:
                    flask_failures.append("classify %r confidence mismatch %.2g"
                                          % (s["text"], disp))
        for bad in samples["malformed"]:
            if bad == "not-json":
                data = b"this is not json"; ctype = "text/plain"
            else:
                data = bad.encode(); ctype = "application/json"
            req = urllib.request.Request("http://127.0.0.1:%d/classify" % PORT,
                                         data=data, headers={"Content-Type": ctype},
                                         method="POST")
            try:
                with urllib.request.urlopen(req, timeout=5) as resp:
                    flask_failures.append("malformed %r got 200, want 400" % bad)
            except urllib.error.HTTPError as e:
                if e.code != 400:
                    flask_failures.append("malformed %r got %d, want 400" % (bad, e.code))
                try:
                    payload = json.loads(e.read().decode())
                except Exception:
                    payload = None
                if not isinstance(payload, dict) or "error" not in payload:
                    flask_failures.append("malformed %r: no JSON error body" % bad)
            except Exception as exc:
                flask_failures.append("malformed %r unexpected: %r" % (bad, exc))
finally:
    server.terminate()
    try:
        server.wait(timeout=5)
    except Exception:
        server.kill()

failures += flask_failures

if failures:
    print("FAILURES:")
    for m in failures:
        print("  - " + m)
    open("/logs/verifier/reward.txt", "w").write("0")
    sys.exit(0)

print("ALL PASS")
open("/logs/verifier/reward.txt", "w").write("1")
sys.exit(0)
PYEOF