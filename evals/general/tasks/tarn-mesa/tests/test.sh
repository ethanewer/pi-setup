#!/bin/bash
# Verifier for tarn-mesa: enforces the no-modify rule on the shipped capture,
# EXECUTES the deliverable /app/extract.py on the visible capture and on every
# hidden container in /tests/hidden, and byte-checks /app/recovered.npy.
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_CAPTURE_SHA="cf9e5816033124ae8fb1700d7a293c6f0b62f55f8e315dfb137dd90eb7ed0ca9"

no_modify_broken=0
if [ ! -f /app/capture.prsm ]; then
    echo "no-modify: /app/capture.prsm missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/capture.prsm | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_CAPTURE_SHA" ]; then
        echo "no-modify: /app/capture.prsm was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import os, subprocess, sys
import numpy as np

EXTRACT = "/app/extract.py"
no_modify_broken = int(sys.argv[1])
failures = []

if no_modify_broken:
    failures.append("visible capture modified or missing (no-modify rule)")


def arrays_equal(path_a, path_b):
    try:
        a = np.load(path_a, allow_pickle=False)
        b = np.load(path_b, allow_pickle=False)
    except Exception as exc:
        print("load error:", exc)
        return False
    return (
        isinstance(a, np.ndarray)
        and isinstance(b, np.ndarray)
        and a.dtype.kind == "f"
        and a.shape == b.shape
        and a.shape == (a.shape[0], a.shape[1] if a.ndim == 2 else 0)
        and np.array_equal(a.astype("<f4"), b.astype("<f4"))
    )


def run_case(container, expected_npy, tag):
    out = "/tmp/tarn_mesa_verify_out.npy"
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run(
            [sys.executable, EXTRACT, container, out],
            capture_output=True, text=True, timeout=120,
        )
    except Exception as exc:
        failures.append("%s: extractor crashed: %s" % (tag, exc))
        return
    if r.returncode != 0:
        failures.append("%s: extractor exited %d" % (tag, r.returncode))
        return
    if not os.path.isfile(out):
        failures.append("%s: extractor produced no output" % tag)
        return
    if not arrays_equal(out, expected_npy):
        failures.append("%s: recovered matrix wrong (values, shape, dtype or orientation)" % tag)


if not os.path.isfile(EXTRACT):
    failures.append("missing /app/extract.py")
else:
    # visible case: EXECUTE the deliverable on the shipped capture
    if not no_modify_broken:
        run_case("/app/capture.prsm", "/tests/expected_visible.npy", "visible-run")

    # visible-case deliverable: /app/recovered.npy must match the shipped capture
    if os.path.isfile("/app/recovered.npy"):
        if not arrays_equal("/app/recovered.npy", "/tests/expected_visible.npy"):
            failures.append("/app/recovered.npy does not match the shipped capture")
    else:
        failures.append("missing /app/recovered.npy")

    # hidden cases: distinct containers exercising both endiannesses, both
    # memory orders, masking, padding, and varied dimensions
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            container = os.path.join(base, "capture.prsm")
            expected = os.path.join(base, "capture.prsm.expected.npy")
            if not (os.path.isfile(container) and os.path.isfile(expected)):
                failures.append("hidden case '%s' malformed" % c)
                continue
            run_case(container, expected, "hidden:%s" % c)
    else:
        failures.append("no hidden cases directory")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
