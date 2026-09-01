#!/usr/bin/env python3
"""Verifier helper for amber-quarry.

  python3 /tests/verify.py <casedir> <answer_npz_or_->

Re-runs the agent deliverable /app/mirror.py (with onnxruntime imports
blocked) against the case's fixed inputs and against seeded random inputs,
and compares both to an onnxruntime reference within the case tolerance.
If <answer_npz> is not "-", also validates that artifact against the fixed
reference. Prints "RESULT: PASS" on success.
"""
import json
import os
import subprocess
import sys

import numpy as np
import onnxruntime as ort

MIRROR = "/app/mirror.py"


def fail(msg):
    print("VERIFY-FAIL: %s" % msg)
    sys.exit(1)


def ort_reference(model_path, x):
    sess = ort.InferenceSession(model_path, providers=["CPUExecutionProvider"])
    return sess.run(["out"], {"x": x})[0]


def run_mirror(model_path, x, tag):
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        inp = os.path.join(td, "in.npz")
        outp = os.path.join(td, "out.npz")
        np.savez(inp, x=x)
        env = dict(os.environ)
        env["PYTHONPATH"] = "/tests/block_ort"
        try:
            r = subprocess.run(
                [sys.executable, MIRROR, model_path, inp, outp],
                capture_output=True, text=True, timeout=120, env=env)
        except subprocess.TimeoutExpired:
            fail("mirror.py timed out (%s)" % tag)
        if r.returncode != 0 or not os.path.isfile(outp):
            fail("mirror.py failed (%s): rc=%d stderr=%s"
                 % (tag, r.returncode, r.stderr[-400:]))
        try:
            got = np.load(outp)["out"]
        except Exception as e:  # noqa: BLE001
            fail("mirror.py output unreadable (%s): %r" % (tag, e))
        return np.asarray(got, dtype=np.float64)


def compare(got, ref, atol, rtol, tag):
    if got.shape != ref.shape:
        fail("output shape %s != reference %s (%s)"
             % (got.shape, ref.shape, tag))
    if not np.isfinite(got).all():
        fail("output contains non-finite values (%s)" % tag)
    err = float(np.abs(got - ref).max())
    if not np.allclose(got, ref, atol=atol, rtol=rtol):
        fail("output deviates from onnx reference (%s): max abs err %.3e "
             "> atol %.1e / rtol %.1e" % (tag, err, atol, rtol))
    return err


def main():
    case, answer_arg = sys.argv[1], sys.argv[2]
    meta = json.load(open(os.path.join(case, "meta.json")))
    model_path = os.path.join(case, "model.onnx")
    atol, rtol = float(meta["atol"]), float(meta["rtol"])

    # forbid executing the reference graph instead of mirroring it
    try:
        src = open(MIRROR).read()
    except OSError:
        fail("cannot read /app/mirror.py")
    low = src
    for banned in ("import onnxruntime", "from onnxruntime", "import torch",
                   "from torch", "import tensorflow", "import keras",
                   "import jax", "from jax"):
        if banned in low:
            fail("mirror.py must not use %s (pure numpy mirroring only)"
                 % banned)

    # ---- fixed inputs -------------------------------------------------------
    x_fix = np.load(os.path.join(case, "inputs_fixed.npz"))["x"]
    x_fix = np.ascontiguousarray(x_fix, dtype=np.float32)
    ref_fix = ort_reference(model_path, x_fix)
    err1 = compare(run_mirror(model_path, x_fix, "fixed"), ref_fix,
                   atol, rtol, "fixed")

    # ---- seeded random inputs ----------------------------------------------
    rng = np.random.default_rng(int(meta["random_seed"]))
    x_rnd = rng.standard_normal(
        (int(meta["random_batch"]), int(meta["in_dim"]))).astype(np.float32)
    ref_rnd = ort_reference(model_path, x_rnd)
    err2 = compare(run_mirror(model_path, x_rnd, "random"), ref_rnd,
                   atol, rtol, "random")

    # ---- answer artifact (visible case) -------------------------------------
    if answer_arg != "-":
        try:
            ans = np.load(answer_arg)["out"]
        except Exception as e:  # noqa: BLE001
            fail("answer artifact %s unreadable: %r" % (answer_arg, e))
        compare(np.asarray(ans, dtype=np.float64), ref_fix, atol, rtol,
                "answer artifact")

    print("RESULT: PASS (max err fixed=%.3e random=%.3e; atol=%.1e)"
          % (err1, err2, atol))


if __name__ == "__main__":
    main()
