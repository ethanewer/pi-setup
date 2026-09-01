#!/usr/bin/env python3
"""gale-jetty verifier (executes-deliverable).

Re-invokes /app/reconcile.py on the visible fixtures and on three hidden
scenarios, then independently re-derives every expected output from the raw
fixtures (tests/reference.py) and compares. Writes a numeric reward to
/logs/verifier/reward.txt. Must only reward=1 when the agent shipped a genuine,
general solution that re-uses the sequential constant by import.
"""
import importlib.util
import json
import os
import shutil
import subprocess
import sys

import numpy as np

TESTS = "/tests"
REW = "/logs/verifier/reward.txt"

failures = []


def fail(msg):
    failures.append(msg)


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


sys.path.insert(0, TESTS)
import reference  # noqa: E402


# --------------------------------------------------------------------------
# Path-agnostic output comparison helpers
# --------------------------------------------------------------------------
def check_outputs(outdir, exp, prefix):
    """Compare every delivered artifact in outdir against reference `exp`."""
    # mart.npy
    mp = os.path.join(outdir, "mart.npy")
    if not os.path.exists(mp):
        fail(prefix + " missing mart.npy")
    else:
        m = np.load(mp)
        if m.shape != exp["mart"].shape:
            fail(prefix + " mart shape %s != %s" % (m.shape, exp["mart"].shape))
        elif not np.allclose(m, exp["mart"], atol=1e-6):
            fail(prefix + " mart values differ")

    # sheet.jsonl (exact addresses + values)
    sp = os.path.join(outdir, "sheet.jsonl")
    if not os.path.exists(sp):
        fail(prefix + " missing sheet.jsonl")
    else:
        try:
            actual = [json.loads(line) for line in open(sp) if line.strip()]
        except Exception as e:
            fail(prefix + " sheet.jsonl not jsonl: %s" % e)
            actual = None
        if actual is not None:
            if len(actual) != len(exp["sheet"]):
                fail(prefix + " sheet record count %d != %d"
                     % (len(actual), len(exp["sheet"])))
            else:
                for a, e in zip(actual, exp["sheet"]):
                    if (a.get("sheet"), a.get("address"), a.get("invoice")) != \
                       (e.get("sheet"), e.get("address"), e.get("invoice")):
                        fail(prefix + " sheet addr mismatch %r vs %r" % (a, e))
                        break
                    av, ev = a.get("value"), e.get("value")
                    if isinstance(av, (int, float)) and isinstance(ev, (int, float)):
                        if not np.isclose(float(av), float(ev), atol=1e-6):
                            fail(prefix + " sheet value %r != %r" % (av, ev))
                            break
                    elif av != ev:
                        fail(prefix + " sheet value str mismatch %r != %r" % (av, ev))
                        break

    # ranked.json
    rp = os.path.join(outdir, "ranked.json")
    if not os.path.exists(rp):
        fail(prefix + " missing ranked.json")
    else:
        if json.load(open(rp)) != exp["ranked"]:
            fail(prefix + " ranked.json differs from reference")

    # mismatch.txt
    mm = os.path.join(outdir, "mismatch.txt")
    if not os.path.exists(mm):
        fail(prefix + " missing mismatch.txt")
    else:
        if open(mm).read().strip() != exp["mismatch"]:
            fail(prefix + " mismatch.txt %r != %r"
                 % (open(mm).read().strip(), exp["mismatch"]))

    # prompts.txt (exact per-row lines)
    pp = os.path.join(outdir, "prompts.txt")
    if not os.path.exists(pp):
        fail(prefix + " missing prompts.txt")
    else:
        lines = [l for l in open(pp).read().splitlines() if l.strip()] \
            if os.path.exists(pp) else []
        if lines != exp["prompts"]:
            fail(prefix + " prompts.txt lines differ (got %d, want %d)"
                 % (len(lines), len(exp["prompts"])))

    # inference.npz per-row mask grids
    ip = os.path.join(outdir, "inference.npz")
    if not os.path.exists(ip):
        fail(prefix + " missing inference.npz")
    else:
        arr = np.load(ip)["masks"]
        want_shape = (exp["grid_count"],) + exp["grid_shape"]
        if arr.shape != want_shape:
            fail(prefix + " inference shape %s != %s" % (arr.shape, want_shape))


def check_ledger(indir, outdir, exp_classes, prefix):
    inbox = os.path.join(indir, "inbox")
    if os.path.exists(inbox) and os.listdir(inbox):
        fail(prefix + " inbox not emptied: %r" % os.listdir(inbox))
    led = os.path.join(outdir, "ledger")
    for bucket in ("invoice", "other"):
        d = os.path.join(led, bucket)
        if not os.path.isdir(d):
            fail(prefix + " ledger/%s directory missing" % bucket)
            continue
        actual = sorted(os.listdir(d))
        if actual != sorted(exp_classes.get(bucket, [])):
            fail(prefix + " ledger/%s %r != %r" % (bucket, actual, sorted(exp_classes.get(bucket, []))))


# --------------------------------------------------------------------------
# Import evidence for the sequential-constant reuse competency
# --------------------------------------------------------------------------
def import_evidence():
    for required, needle, label in (
        ("/app/compute_parallel.py", "compute_seq",
         "compute_parallel must import the sequential constant"),
        ("/app/extract.py", "compute_parallel",
         "extraction engine must import the parallel wrapper"),
        ("/app/reconcile.py", "compute_parallel",
         "reconcile driver must import the parallel wrapper"),
    ):
        if not os.path.exists(required):
            fail("missing module " + required)
            continue
        try:
            src = open(required).read()
        except OSError as e:
            fail("cannot read %s: %s" % (required, e))
            continue
        if needle not in src:
            fail(label)


# --------------------------------------------------------------------------
# MAIN (visible) scenario
# --------------------------------------------------------------------------
MAIN_LEDGER = {
    "invoice": ["inv_alpha.txt", "inv_beta.txt", "inv_gamma.txt",
                "inv_delta.txt", "inv_omega.txt"],
    "other": ["memo_zeta.txt", "memo_theta.txt"],
}


def main_case():
    for p in ("/app/reconcile.py", "/app/extract.py", "/app/compute_parallel.py",
              "/app/compute_seq.py", "/app/mart.npy", "/app/sheet.jsonl"):
        if not os.path.exists(p):
            fail("missing artifact " + p)

    # the reconcile driver must be present and runnable
    if not os.path.exists("/app/reconcile.py"):
        fail("missing deliverable /app/reconcile.py")
        return False

    import_evidence()

    # execute the deliverable (idempotent re-run on the visible fixtures)
    r = run(["python3", "/app/reconcile.py", "--input", "/app", "--output", "/app"])
    if r.returncode != 0:
        fail("reconcile.py failed to (re)run: " + (r.stderr or r.stdout)[-500:])

    exp = reference.expected("/app")
    check_outputs("/app", exp, "main ")
    check_ledger("/app", "/app", MAIN_LEDGER, "main ")
    return True


# --------------------------------------------------------------------------
# HIDDEN scenarios
# --------------------------------------------------------------------------
HIDDEN = [
    ("trio", "/tests/hidden/case_trio.py"),
    ("malformed", "/tests/hidden/case_malformed.py"),
    ("empty", "/tests/hidden/case_empty.py"),
]


def hidden_cases():
    import tempfile
    for name, path in HIDDEN:
        mod = load_module("case_" + name, path)
        work = "/app/_hidden_" + name
        if os.path.exists(work):
            shutil.rmtree(work)
        indir = os.path.join(work, "in_scen")
        outdir = os.path.join(work, "out_scen")
        os.makedirs(indir)
        mod.build(indir)
        exp = reference.expected(indir)
        exp_classes = reference.snapshot_classes(indir)
        if not os.path.exists(outdir):
            os.makedirs(outdir)
        r = run(["python3", "/app/reconcile.py", "--input", indir, "--output", outdir])
        if r.returncode != 0:
            fail("hidden %s: reconcile failed: %s" % (name, (r.stderr or r.stdout)[-400:]))
        check_outputs(outdir, exp, "hidden %s " % name)
        check_ledger(indir, outdir, exp_classes, "hidden %s " % name)


def main():
    os.makedirs("/logs/verifier", exist_ok=True)
    # the verifier must ALWAYS leave a numeric reward, even if a bug is hit
    try:
        main_case()
        hidden_cases()
    except Exception as e:  # noqa: BLE001
        failures.append("verifier exception: %r" % e)

    if failures:
        print("FAILURES:")
        for m in failures:
            print("  - " + m)
        with open(REW, "w") as f:
            f.write("0")
        return 0
    print("ALL PASS")
    with open(REW, "w") as f:
        f.write("1")
    return 0


if __name__ == "__main__":
    sys.exit(main())
