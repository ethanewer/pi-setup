#!/bin/bash
# Verifier for vine-forge (executes-deliverable): re-executes
# /app/score_bags.py on the shipped bag and hidden bags (exact per-bag counts
# vs an independent recompute), probes the error/empty edges, and runs a
# ~2M-patch stress bag under a peak-RSS monitor with a wall-clock deadline.
# Writes 1/0 to /logs/verifier/reward.txt; never crashes on malformed output.
set -u
mkdir -p /logs/verifier

python3 - <<'PY'
import os
import subprocess
import sys
import time

import numpy as np
import pandas as pd

GRADER = "/app/score_bags.py"
SCORER = "/app/scorer.npz"
VISIBLE_BAG = "/app/data/big_bag.csv"
VISIBLE_OUT = "/app/event_scores.txt"
STRESS_ROWS = 2_000_000
STRESS_BAGS = 6
RSS_CAP_KB = 450_000
TIME_MAX_S = 240.0
STRESS_TOL = 5  # per-bag count tolerance on the stress bag (fp tie noise)
DIM, HID = 32, 16
FEATS = ["f%d" % d for d in range(DIM)]
failures = []


def fail(msg):
    failures.append(msg)


def load_scorer():
    z = np.load(SCORER)
    return z["W1"].astype(np.float64), z["b1"].astype(np.float64), \
        z["W2"].astype(np.float64), z["b2"].astype(np.float64)


def reference(path, W1, b1, W2, b2):
    """Independent streaming recompute: list of (bag_id, positive_count)."""
    counts, order = {}, []
    for chunk in pd.read_csv(path, chunksize=50_000):
        X = chunk[FEATS].to_numpy(dtype=np.float64)
        bids = chunk["bag_id"].to_numpy()
        h = np.maximum(X @ W1.T + b1, 0.0)
        zz = (h @ W2.T + b2).ravel()
        pos = zz > 0.0
        for bid, p in zip(bids, pos):
            b = int(bid)
            if b not in counts:
                counts[b] = 0
                order.append(b)
            counts[b] += int(p)
    return [(b, counts[b]) for b in order]


def run_grader(bag, out, wrap=False):
    cmd = [sys.executable, GRADER, bag, out]
    if wrap:
        cmd = [sys.executable, "/tests/memwrap.py", GRADER, bag, out]
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=400)
    except Exception as exc:
        fail("grader crashed on %s: %r" % (bag, exc))
        return None


def check_exact(tag, bag, out):
    r = run_grader(bag, out)
    if r is None or r.returncode != 0:
        fail("%s: grader exited %s (%s)"
             % (tag, r.returncode if r else "?", (r.stderr[-200:] if r else "")))
        return False
    try:
        got = [(int(a), int(b)) for a, b in
               (ln.split() for ln in open(out) if ln.strip())]
    except Exception as exc:
        fail("%s: output unreadable (%r)" % (tag, exc))
        return False
    W = load_scorer()
    ref = reference(bag, *W)
    if got != ref:
        fail("%s: per-bag counts %r != reference %r" % (tag, got[:6], ref[:6]))
        return False
    print("  %s: %d bags OK" % (tag, len(got)))
    return True


# ---- 1. deliverables exist --------------------------------------------------
if not os.path.isfile(GRADER):
    fail("missing /app/score_bags.py")

# ---- 2. visible bag ----------------------------------------------------------
if os.path.isfile(GRADER) and os.path.isfile(VISIBLE_BAG):
    check_exact("visible-rerun", VISIBLE_BAG, "/tmp/vis_scores.txt")
    if not os.path.isfile(VISIBLE_OUT):
        fail("missing /app/event_scores.txt")
    else:
        try:
            got = [(int(a), int(b)) for a, b in
                   (ln.split() for ln in open(VISIBLE_OUT) if ln.strip())]
            W = load_scorer()
            ref = reference(VISIBLE_BAG, *W)
            if got != ref:
                fail("/app/event_scores.txt != independent recompute")
            else:
                print("  visible-artifact: %d bags OK" % len(got))
        except Exception as exc:
            fail("/app/event_scores.txt unreadable (%r)" % exc)

# ---- 3. hidden bags ----------------------------------------------------------
hidden_dir = "/tests/hidden"
if os.path.isdir(hidden_dir):
    cases = sorted(os.listdir(hidden_dir))
    if not cases:
        fail("no hidden cases present")
    for case in cases:
        bag = os.path.join(hidden_dir, case, "bag.csv")
        if not os.path.isfile(bag):
            fail("hidden '%s': missing bag.csv" % case)
            continue
        check_exact("hidden:%s" % case, bag, "/tmp/h_%s.txt" % case)
else:
    fail("missing /tests/hidden")

# ---- 4. edges ----------------------------------------------------------------
if os.path.isfile(GRADER):
    hdr_only = "/tmp/hdr_only.csv"
    with open(hdr_only, "w") as fh:
        fh.write("bag_id," + ",".join(FEATS) + "\n")
    out = "/tmp/hdr_out.txt"
    if os.path.exists(out):
        os.remove(out)
    r = run_grader(hdr_only, out)
    if r is None or r.returncode != 0:
        fail("header-only bag must exit 0")
    elif os.path.exists(out) and open(out).read() != "":
        fail("header-only bag must give empty output")
    # non-numeric feature
    bad = "/tmp/bad_feat.csv"
    with open(bad, "w") as fh:
        fh.write("bag_id," + ",".join(FEATS) + "\n7,"
                 + ",".join("0.5" for _ in range(DIM - 1)) + ",abc\n")
    r = run_grader(bad, "/tmp/bad_out.txt")
    if r is None or r.returncode == 0:
        fail("non-numeric feature must exit non-zero")
    # missing feature column
    badc = "/tmp/bad_cols.csv"
    with open(badc, "w") as fh:
        fh.write("bag_id,f0,f1\n7,0.5,0.5\n")
    r = run_grader(badc, "/tmp/badc_out.txt")
    if r is None or r.returncode == 0:
        fail("missing feature columns must exit non-zero")

# ---- 5. stress bag: bounded memory + deadline + correctness ------------------
stress = "/tmp/stress_bag.csv"
t0 = time.monotonic()
try:
    rng = np.random.default_rng(31337)
    per = STRESS_ROWS // STRESS_BAGS
    with open(stress, "w") as fh:
        for b in range(STRESS_BAGS):
            X = rng.uniform(-1.0, 1.0, (per, DIM))
            body = pd.DataFrame(X, columns=FEATS)
            body.insert(0, "bag_id", b)
            body.to_csv(fh, header=(b == 0), index=False)
            del body, X
    print("  stress bag written in %.1fs" % (time.monotonic() - t0))
except Exception as exc:
    fail("stress bag generation failed (%r)" % exc)
    stress = None

if stress and os.path.isfile(GRADER):
    t0 = time.monotonic()
    r = run_grader(stress, "/tmp/stress_out.txt", wrap=True)
    dt = time.monotonic() - t0
    peak = -1
    if r is not None:
        for line in (r.stdout or "").splitlines():
            parts = line.split()
            if len(parts) == 2 and parts[0] == "PEAK_KB":
                try:
                    peak = int(parts[1])
                except ValueError:
                    pass
    if r is None or r.returncode != 0:
        fail("stress bag: grader exited %s" % (r.returncode if r else "?"))
    else:
        if not (0 < peak <= RSS_CAP_KB):
            fail("stress bag: peak RSS %s KiB outside (0, %d]"
                 % (peak, RSS_CAP_KB))
        if dt > TIME_MAX_S:
            fail("stress bag: %.1fs exceeded the %ds deadline" % (dt, TIME_MAX_S))
        try:
            got = [(int(a), int(b)) for a, b in
                   (ln.split() for ln in open("/tmp/stress_out.txt")
                    if ln.strip())]
            W = load_scorer()
            ref = reference(stress, *W)
            ok = len(got) == len(ref) and all(
                g[0] == rr[0] and abs(g[1] - rr[1]) <= STRESS_TOL
                for g, rr in zip(got, ref))
            if not ok:
                fail("stress bag: counts %r != reference %r"
                     % (got[:6], ref[:6]))
            else:
                print("  stress: %d bags, %.1fs, peak %d KiB"
                      % (len(got), dt, peak))
        except Exception as exc:
            fail("stress bag: output unreadable (%r)" % exc)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

rc=$?
if [ "$rc" -eq 0 ]; then
    echo 1 > /logs/verifier/reward.txt
else
    echo 0 > /logs/verifier/reward.txt
fi
exit 0
