#!/usr/bin/env python3
"""marl-haven verifier (executes-deliverable).

Executes /app/extract.py on the visible fixtures and on every hidden case,
independently re-deriving each expected matrix from the raw inputs. Also checks
the visible-run deliverable /app/payload.npy, the executable/shebang contract,
and that the supplied /app inputs were not modified. Writes reward (0/1) to
/logs/verifier/reward.txt.
"""
import hashlib
import os
import stat
import subprocess
import sys

import numpy as np

sys.path.insert(0, "/tests")
import reference  # noqa: E402

REW = "/logs/verifier/reward.txt"
EXTRACT = "/app/extract.py"
PAYLOAD = "/app/payload.npy"

# Pristine sha256 of the supplied visible fixtures (no-modify rule).
PRISTINE_CAPTURE = "2c7e5ebef877c5e800c2487cfe20e78005f2ae83caca1222c02eb798af52d270"
PRISTINE_QUERY = "34f9b17e3de5001c014142dbe0805f613724ea60fb3f96d1eac122972c812765"

failures = []


def fail(msg):
    failures.append(msg)


def sha256_file(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def run_extract(capture, query, out_npy):
    if os.path.exists(out_npy):
        os.remove(out_npy)
    try:
        r = subprocess.run(
            [sys.executable, EXTRACT, capture, query, out_npy],
            capture_output=True, text=True, timeout=120,
        )
    except subprocess.TimeoutExpired:
        fail("extract.py timed out on %s" % capture)
        return None
    if r.returncode != 0:
        fail("extract.py exited %d on %s: %s" % (r.returncode, capture, r.stderr[-300:]))
        return None
    if not os.path.isfile(out_npy):
        fail("extract.py did not write %s" % out_npy)
        return None
    try:
        return np.load(out_npy)
    except Exception as exc:
        fail("output %s is not a loadable .npy: %s" % (out_npy, exc))
        return None


def check_matrix(got, want, label):
    if got is None:
        return
    if not isinstance(got, np.ndarray):
        fail("%s: not an ndarray" % label)
        return
    if got.dtype != np.float64:
        fail("%s: dtype is %s, expected float64" % (label, got.dtype))
        return
    if got.shape != want.shape:
        fail("%s: shape %s != expected %s (wrong orientation?)" % (label, got.shape, want.shape))
        return
    if not np.array_equal(got, want):
        fail("%s: values differ from independently derived expected matrix" % label)


def main():
    # --- no-modify guard on the supplied fixtures -------------------------
    if not os.path.isfile("/app/capture.bin") or sha256_file("/app/capture.bin") != PRISTINE_CAPTURE:
        fail("/app/capture.bin missing or modified")
    if not os.path.isfile("/app/query.txt") or sha256_file("/app/query.txt") != PRISTINE_QUERY:
        fail("/app/query.txt missing or modified")

    # --- deliverable script contract --------------------------------------
    if not os.path.isfile(EXTRACT):
        fail("missing /app/extract.py")
    else:
        mode = os.stat(EXTRACT).st_mode
        if not (mode & stat.S_IXUSR):
            fail("/app/extract.py is not executable (chmod +x)")
        with open(EXTRACT, "rb") as fh:
            if not fh.readline().startswith(b"#!"):
                fail("/app/extract.py missing #! shebang on line 1")

        # --- visible case: execute the deliverable ------------------------
        want_vis = reference.expected_matrix("/app/capture.bin", "/app/query.txt")
        got = run_extract("/app/capture.bin", "/app/query.txt", "/tmp/mh_vis.npy")
        check_matrix(got, want_vis, "visible run")

        # --- visible-run deliverable /app/payload.npy ----------------------
        if not os.path.isfile(PAYLOAD):
            fail("missing /app/payload.npy")
        else:
            try:
                check_matrix(np.load(PAYLOAD), want_vis, "payload.npy")
            except Exception as exc:
                fail("payload.npy unreadable: %s" % exc)

        # --- hidden cases: execute the deliverable on each ----------------
        hidden = "/tests/hidden"
        if not os.path.isdir(hidden) or not os.listdir(hidden):
            fail("no hidden cases present")
        for case in sorted(os.listdir(hidden)):
            base = os.path.join(hidden, case)
            cap = os.path.join(base, "capture.bin")
            qry = os.path.join(base, "query.txt")
            if not (os.path.isfile(cap) and os.path.isfile(qry)):
                fail("hidden case '%s' malformed" % case)
                continue
            want = reference.expected_matrix(cap, qry)
            got = run_extract(cap, qry, "/tmp/mh_%s.npy" % case)
            check_matrix(got, want, "hidden '%s'" % case)

    print("verify failures:", failures)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
