#!/bin/bash
# Verifier for brine-ridge: enforces the no-modify rule on the shipped
# saltern sources + visible dataset, checks the CPU-only build contract
# (no CUDA linkage, exact target name), rebuilds the framework from a clean
# copy of the agent's tree with USE_GPU=OFF, and EXECUTES the deliverable
# trainer on hidden datasets against an independent reference. Writes REWARD
# (0/1) to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import json, math, os, re, shutil, subprocess, sys, tempfile

BINARY = "/app/saltern/build/saltern_cpu"
MODEL = "/app/model.json"
LOG = "/app/train-log.txt"
HIDDEN = "/tests/hidden"

failures = []

# --- no-modify hashes of shipped fixtures ----------------------------------
PRISTINE = {
    "/app/data/train.csv":
        "f350cb8d1a0e36794e758d0f3ea7992c216c2967cacca8f1ed29bea5bc936a2f",
    "/app/saltern/CMakeLists.txt":
        "5afcf4194ea4300825d5ecd721e01da2cb50e8cf258ce96dbcce79f963234857",
    "/app/saltern/core/data.cpp":
        "345af81c2e2b516d9da6cf128c9225dc677e2063fff0086c4f11bcbbd1febd72",
    "/app/saltern/core/data.hpp":
        "adb5a62bcc07da33c3271dc02da9c6d3948ffb10a5cf269040a12097a4db6f1a",
    "/app/saltern/core/model.cpp":
        "0613d1e889d174a9f092f3acacaf5afc34d6cc48c1fe01d1690835b71a4d55f0",
    "/app/saltern/core/model.hpp":
        "bbcd9b271f15f4c0ce28ed43f646644d35f7a720961e03ae1084a9240b56c4a4",
    "/app/saltern/cpu/train_cpu.cpp":
        "d1992a735f7596b17de537a98f9962f192e631ac96bec004c306bfd657f8dbac",
    "/app/saltern/core/CMakeLists.txt":
        "679d8e8c7aece115e331161bfb19d634c08a528548e5ab6eb432d929d635d483",
    "/app/saltern/gpu/enable_gpu.cmake":
        "fc8aa94e6a0b6e54e95e85196055347250f8791cd67f89b4090cfb1fd02cbe6e",
}
for path, want in PRISTINE.items():
    if not os.path.isfile(path):
        failures.append("shipped fixture missing: %s" % path)
        continue
    got = subprocess.run(["sha256sum", path], capture_output=True, text=True)
    if got.returncode != 0 or got.stdout.split()[0] != want:
        failures.append("shipped fixture modified: %s" % path)

# --- independent reference implementation of the trainer contract -----------
def load_ds(path):
    ds = []
    with open(path) as fh:
        for line in fh:
            s = line.strip()
            if not s or s.startswith('#'):
                continue
            a, b, y = s.split(',')
            ds.append((float(a), float(b), float(y)))
    return ds


def ref_train(ds, epochs, lr):
    w1 = w2 = b = 0.0
    n = len(ds)
    loss = 0.0
    for _ in range(epochs):
        g1 = g2 = gb = 0.0
        for x1, x2, y in ds:
            p = 1.0 / (1.0 + math.exp(-(w1 * x1 + w2 * x2 + b)))
            e = p - y
            g1 += e * x1; g2 += e * x2; gb += e
        g1 /= n; g2 /= n; gb /= n
        w1 -= lr * g1; w2 -= lr * g2; b -= lr * gb
        acc = 0.0
        for x1, x2, y in ds:
            p = 1.0 / (1.0 + math.exp(-(w1 * x1 + w2 * x2 + b)))
            p = min(max(p, 1e-12), 1 - 1e-12)
            acc += -(y * math.log(p) + (1 - y) * math.log(1 - p))
        loss = acc / n
    return {"w1": w1, "w2": w2, "b": b, "final_loss": loss}


def run_trainer(exe, data, epochs, lr, out):
    if os.path.exists(out):
        os.remove(out)
    r = subprocess.run([exe, "--data", data, "--epochs", str(epochs),
                        "--lr", str(lr), "--out", out],
                       capture_output=True, text=True, timeout=120)
    model = None
    if os.path.isfile(out):
        try:
            model = json.load(open(out))
        except Exception:
            model = None
    return r, model


def check_model(got, want, ctx):
    if not isinstance(got, dict):
        failures.append("%s: model.json unreadable" % ctx)
        return
    for k in ("w1", "w2", "b", "final_loss"):
        if k not in got:
            failures.append("%s: model missing key %s" % (ctx, k))
            return
        try:
            if abs(float(got[k]) - float(want[k])) > 1e-3:
                failures.append("%s: %s mismatch (got %r want %.6f)"
                                % (ctx, k, got[k], want[k]))
        except Exception:
            failures.append("%s: %s not numeric" % (ctx, k))

# --- deliverable binary: exists, CPU-only linkage ---------------------------
if not os.path.isfile(BINARY):
    failures.append("missing deliverable %s" % BINARY)
else:
    ldd = subprocess.run(["ldd", BINARY], capture_output=True, text=True)
    linktext = (ldd.stdout + ldd.stderr).lower()
    for bad in ("cuda", "cudart", "nvrtc", "cublas", "cudnn", "nvidia"):
        if bad in linktext:
            failures.append("binary links CUDA-related library (%s)" % bad)

# --- hidden cases: deliverable + clean-rebuilt binary vs reference ----------
hidden = sorted(os.listdir(HIDDEN)) if os.path.isdir(HIDDEN) else []
if not hidden:
    failures.append("no hidden cases present")

rebuilt = None
for case in hidden:
    base = os.path.join(HIDDEN, case)
    data = os.path.join(base, "data.csv")
    exp = os.path.join(base, "expected.json")
    if not (os.path.isfile(data) and os.path.isfile(exp)):
        failures.append("hidden '%s' malformed" % case)
        continue
    try:
        meta = json.load(open(exp))
        epochs = int(meta["epochs"]); lr = float(meta["lr"])
        want = ref_train(load_ds(data), epochs, lr)
        for k in ("w1", "w2", "b", "final_loss"):
            if abs(want[k] - float(meta["ref"][k])) > 1e-6:
                failures.append("hidden '%s': stored expected disagrees with "
                                "reference (fixture bug)" % case)
    except Exception as e:
        failures.append("hidden '%s': bad expected.json (%s)" % (case, e))
        continue

    if os.path.isfile(BINARY):
        r, model = run_trainer(BINARY, data, epochs, lr, "/tmp/brine_h.json")
        if r.returncode != 0:
            failures.append("hidden '%s': deliverable exited %d" % (case, r.returncode))
        else:
            check_model(model, want, "hidden '%s' (deliverable)" % case)

    # once: fresh rebuild with the GPU path disabled from the agent's tree
    if rebuilt is None and os.path.isdir("/app/saltern"):
        tmp = tempfile.mkdtemp(prefix="brine-rebuild-")
        dst = os.path.join(tmp, "saltern")
        shutil.copytree("/app/saltern", dst, ignore=shutil.ignore_patterns("build"))
        cfg = subprocess.run(["cmake", "-S", dst, "-B", os.path.join(tmp, "b2"),
                              "-DUSE_GPU=OFF"], capture_output=True, text=True,
                             timeout=180)
        bld = subprocess.run(["cmake", "--build", os.path.join(tmp, "b2"),
                              "--target", "saltern_cpu"],
                             capture_output=True, text=True, timeout=180)
        cand = os.path.join(tmp, "b2", "saltern_cpu")
        if cfg.returncode != 0 or bld.returncode != 0 or not os.path.isfile(cand):
            failures.append("clean rebuild with -DUSE_GPU=OFF failed")
        else:
            rebuilt = cand
    if rebuilt is None:
        failures.append("hidden '%s': no rebuilt binary to cross-check" % case)
    else:
        r, model = run_trainer(rebuilt, data, epochs, lr, "/tmp/brine_r.json")
        if r.returncode != 0:
            failures.append("hidden '%s': rebuilt binary exited %d" % (case, r.returncode))
        else:
            check_model(model, want, "hidden '%s' (rebuilt)" % case)

# --- visible-case deliverables ---------------------------------------------
if os.path.isfile(BINARY) and os.path.isfile("/app/data/train.csv"):
    r, model = run_trainer(BINARY, "/app/data/train.csv", 200, 0.5,
                           "/tmp/brine_vis.json")
    if r.returncode != 0:
        failures.append("visible re-run exited %d" % r.returncode)
    else:
        check_model(model, ref_train(load_ds("/app/data/train.csv"), 200, 0.5),
                    "visible (deliverable)")
if os.path.isfile(MODEL):
    try:
        check_model(json.load(open(MODEL)),
                    ref_train(load_ds("/app/data/train.csv"), 200, 0.5),
                    "/app/model.json")
    except Exception:
        failures.append("/app/model.json unreadable")
else:
    failures.append("missing deliverable %s" % MODEL)

if os.path.isfile(LOG):
    lines = [l for l in open(LOG).read().splitlines() if l.strip()]
    if not lines or not re.match(r"^epoch=200 loss=[0-9.]+$", lines[-1]):
        failures.append("/app/train-log.txt does not end with epoch=200 line")
else:
    failures.append("missing deliverable %s" % LOG)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
