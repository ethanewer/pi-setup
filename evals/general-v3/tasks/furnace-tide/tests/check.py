#!/usr/bin/env python3
"""Verifier for furnace-tide (executes-deliverable). /tests is mounted
read-only.

Checks, in order:
  * deliverables exist; pristine fixtures untouched (no-modify rule).
  * /app/score_traces.py re-executed on the visible input -> stdout and file
    match an independent streamed recompute of the frozen numpy model.
  * /app/trace_scores.txt matches the same recompute.
  * hidden trace sets (string ids in unsorted first-occurrence order; 3000
    small traces) scored correctly.
  * edges: header-only input -> empty output + exit 0; missing feature columns
    -> non-zero exit; non-numeric feature -> non-zero exit.
  * stress set (1.2M patches): correct scores, peak VmHWM <= 400 MB, wall
    clock within the deadline.
"""
import hashlib
import os
import re
import subprocess
import sys

import numpy as np
import pandas as pd

APP = "/app"
HIDDEN = "/tests/hidden"
SCORER = "/app/score_traces.py"
MODEL = "/app/model.npz"
VISIBLE = "/app/data/traces_visible.csv"
VISIBLE_OUT = "/app/trace_scores.txt"
F = 32
FEATS = [f"x{i}" for i in range(F)]
RSS_CAP_KB = 400_000
TIME_MAX_S = 150.0
TOL = 5.1e-5  # one unit in the 4th decimal (rounding-boundary slack)
LINE_RE = re.compile(r"^\d\.\d{4}$")
CHECKS = []


def check(name, ok, detail=""):
    CHECKS.append((name, bool(ok)))
    print(("PASS " if ok else "FAIL ") + name + ((" | " + detail) if detail else ""))


def _try(fn, default="<err>"):
    try:
        return fn()
    except Exception as e:
        print("   ERR", repr(e)[:180])
        return default


def load_model():
    m = np.load(MODEL)
    return m["W1"], m["b1"], m["W2"], m["b2"]


def reference_scores(path, m, chunk=8192):
    """Independent streaming recompute: (ordered trace ids, mean probabilities)."""
    W1, b1, W2, b2 = m
    order, sums, cnts = [], {}, {}
    for ch in pd.read_csv(path, chunksize=chunk):
        X = ch[FEATS].to_numpy(dtype=np.float64)
        h = np.maximum(X @ W1.T + b1, 0.0)
        p = 1.0 / (1.0 + np.exp(-(h @ W2.T + b2).ravel()))
        for tid, pv in zip(ch["trace_id"].astype(str), p):
            if tid in sums:
                sums[tid] += pv
                cnts[tid] += 1
            else:
                sums[tid] = float(pv)
                cnts[tid] = 1
                order.append(tid)
    return order, [sums[t] / cnts[t] for t in order]


def scores_match(got_text, order, probs):
    """got_text: exact file/stdout content. Compare line count, %.4f format,
    order, and per-line float values within TOL."""
    if got_text is None:
        return False, "unreadable"
    lines = got_text.splitlines()
    if got_text and not got_text.endswith("\n"):
        return False, "missing trailing newline"
    if len(lines) != len(order):
        return False, f"{len(lines)} lines vs {len(order)} traces"
    for ln, tid, pv in zip(lines, order, probs):
        if not LINE_RE.match(ln):
            return False, f"bad format {ln!r}"
        if abs(float(ln) - pv) > TOL:
            return False, f"{tid}: {ln} vs {pv:.6f}"
    return True, f"{len(lines)} traces ok"


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def run_scorer(inp, out):
    if os.path.exists(out):
        os.remove(out)
    return subprocess.run(["python3", SCORER, inp, out],
                          capture_output=True, text=True, timeout=200)


def check_case(tag, path, m):
    order, probs = _try(lambda: reference_scores(path, m), ([], []))
    r = run_scorer(path, f"/tmp/ft_{tag}.txt")
    ok_rc = r.returncode == 0
    check(f"{tag}: scorer exits 0", ok_rc,
          f"rc={r.returncode} err={r.stderr.strip()[-140:]}")
    got_file = _try(lambda: open(f"/tmp/ft_{tag}.txt").read())
    ok_file, why = scores_match(got_file, order, probs)
    check(f"{tag}: output file matches recompute", ok_file, why)
    ok_out, why2 = scores_match(r.stdout, order, probs)
    check(f"{tag}: stdout matches recompute", ok_out, why2)


def main():
    m = None
    try:
        m = load_model()
    except Exception as e:
        check("model.npz loadable", False, repr(e))

    # no-modify rule (pristine copies stashed at build time in /opt/pristine)
    pristine_ok = True
    for live, pris in [(MODEL, "/opt/pristine/model.npz"),
                       (VISIBLE, "/opt/pristine/traces_visible.csv")]:
        if not (os.path.isfile(live) and os.path.isfile(pris)
                and sha(live) == sha(pris)):
            pristine_ok = False
    check("no-modify: fixtures untouched", pristine_ok)

    check("exists /app/score_traces.py", os.path.isfile(SCORER))
    check("exists /app/trace_scores.txt", os.path.isfile(VISIBLE_OUT))

    if m is not None and os.path.isfile(SCORER):
        # visible deliverable artifact + re-execution
        if os.path.isfile(VISIBLE_OUT) and os.path.isfile(VISIBLE):
            order, probs = _try(lambda: reference_scores(VISIBLE, m), ([], []))
            art = _try(lambda: open(VISIBLE_OUT).read())
            ok, why = scores_match(art, order, probs)
            check("trace_scores.txt matches recompute", ok, why)
        if os.path.isfile(VISIBLE):
            check_case("visible_recheck", VISIBLE, m)

        # hidden trace sets
        if os.path.isdir(HIDDEN):
            cases = sorted(os.listdir(HIDDEN))
            if not cases:
                check("hidden cases present", False, "none")
            for c in cases:
                p = os.path.join(HIDDEN, c)
                if os.path.isfile(p):
                    check_case(f"hidden_{c}", p, m)

        # ---- edges ---------------------------------------------------------
        # header-only input -> empty stdout, empty file, exit 0
        pd.DataFrame(columns=["trace_id"] + FEATS).to_csv("/tmp/empty.csv",
                                                          index=False)
        r = run_scorer("/tmp/empty.csv", "/tmp/empty_out.txt")
        eout = _try(lambda: open("/tmp/empty_out.txt").read())
        check("header-only input -> empty output, exit 0",
              r.returncode == 0 and r.stdout == "" and eout == "",
              f"rc={r.returncode}")

        # missing feature columns -> non-zero exit
        with open("/tmp/badcols.csv", "w") as fh:
            fh.write("trace_id," + ",".join(FEATS[:5]) + "\n7," +
                     ",".join(["0.5"] * 5) + "\n")
        r = run_scorer("/tmp/badcols.csv", "/tmp/badcols_out.txt")
        check("missing feature columns exits non-zero", r.returncode != 0,
              f"rc={r.returncode}")

        # non-numeric feature value -> non-zero exit
        with open("/tmp/badnum.csv", "w") as fh:
            fh.write("trace_id," + ",".join(FEATS) + "\n")
            fh.write("9," + ",".join(["0.5"] * (F - 1)) + ",abc\n")
        r = run_scorer("/tmp/badnum.csv", "/tmp/badnum_out.txt")
        check("non-numeric feature exits non-zero", r.returncode != 0,
              f"rc={r.returncode}")

        # ---- 1.2M-patch stress set: bounded RSS + near-linear deadline -----
        stress = "/tmp/stress_traces.csv"
        gen = subprocess.run([sys.executable, "/tests/gen_stress.py", stress],
                             capture_output=True, text=True, timeout=240)
        if gen.returncode == 0 and os.path.isfile(stress):
            wrap = subprocess.run(
                [sys.executable, "/tests/measure_wrap.py",
                 sys.executable, SCORER, stress, "/tmp/stress_out.txt"],
                capture_output=True, text=True, timeout=240)
            rc = peak = dt = None
            for line in wrap.stdout.splitlines():
                parts = line.split()
                if len(parts) == 4 and parts[0] == "MEAS":
                    rc, peak, dt = int(parts[1]), int(parts[2]), float(parts[3])
            check("stress: scorer ran (MEAS line)", rc is not None,
                  wrap.stdout.strip()[:120])
            if rc is not None:
                check("stress: exit 0", rc == 0, f"rc={rc}")
                check(f"stress: peak RSS <= {RSS_CAP_KB // 1000} MB",
                      0 < peak <= RSS_CAP_KB,
                      f"peak={peak} KiB cap={RSS_CAP_KB}")
                check(f"stress: within {TIME_MAX_S:.0f}s deadline",
                      0 < dt <= TIME_MAX_S, f"{dt:.1f}s")
            sref = _try(lambda: reference_scores(stress, m), ([], []))
            sgot = _try(lambda: open("/tmp/stress_out.txt").read())
            ok, why = scores_match(sgot, sref[0], sref[1])
            check("stress: scores match recompute", ok, why)
            os.remove(stress)
        else:
            check("stress set generated", False, gen.stderr.strip()[-140:])

    failed = sum(1 for _, ok in CHECKS if not ok)
    print(f"TOTAL {len(CHECKS)} FAILED {failed}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        import traceback
        print("FAIL harness error")
        traceback.print_exc()
        sys.exit(1)
