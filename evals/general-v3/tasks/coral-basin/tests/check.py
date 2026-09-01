#!/usr/bin/env python3
"""Verifier for coral-basin (executes-deliverable). Runs as root after the
agent; /tests is mounted read-only.

Checks, without trusting any pre-baked answers:
  * /app/bag_mean.py and /app/bag_means.txt exist; the frozen triage model is
    untouched and has the required Linear(20->32), ReLU, Linear(32->2) shape.
  * /app/bag_means.txt matches an independent streaming recompute through the
    same frozen model (first-occurrence order, per-line tolerance 5e-4 to
    absorb float summation order), and re-executing the scorer on the visible
    bag yields byte-identical stdout and output file.
  * Hidden bags: different bag counts/sizes (single-patch bags up to a 60k+
    patch bag), non-monotonic ids — scores must match the recompute.
  * Edges: header-only bag file -> empty outputs, exit 0; missing bag_id or
    feature column, and non-numeric feature values, -> exit non-zero.
  * Stress bag (>1.3M patches, generated here from a fixed seed): the scorer
    must finish within the deadline with peak RSS <= 400 MB (chunked, bounded
    memory) and still match the recompute exactly.
"""
import os
import subprocess
import sys

import numpy as np
import pandas as pd
import torch
import torch.nn as nn
import torch.nn.functional as NF

APP = "/app"
HIDDEN = "/tests/hidden"
F, HID, C = 20, 32, 2
FEATS = ["x%d" % i for i in range(F)]
SCORER = "/app/bag_mean.py"
ART = "/app/bag_means.txt"
MODEL = "/app/triage_model.pt"
VISIBLE = "/app/data/sensor_bags.csv"
TOL = 5e-4
RSS_CAP_KB = 400_000
TIME_MAX_S = 120.0
STRESS_ROWS = 1_300_000
STRESS_BAGS = 4
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


def arch_ok(sd):
    if not isinstance(sd, dict) or len(sd) != 4:
        return False
    return {tuple(v.shape) for v in sd.values()} == {(C,), (HID,), (HID, F), (C, HID)}


def load_model():
    sd = torch.load(MODEL, map_location="cpu")
    if not arch_ok(sd):
        raise ValueError("frozen triage model has the wrong architecture")
    fresh = {}
    for k, v in sd.items():
        root = "0" if tuple(v.shape) in ((HID, F), (HID,)) else "2"
        suffix = ".weight" if k.endswith(".weight") else ".bias"
        fresh[root + suffix] = v
    m = nn.Sequential(nn.Linear(F, HID), nn.ReLU(), nn.Linear(HID, C))
    m.load_state_dict(fresh)
    m.eval()
    return m


def bag_reference(model, path):
    """Independent streaming recompute: per-bag mean of P(class=1),
    first-occurrence order, '%.4f' per line."""
    sums, counts, order = {}, {}, []
    for chunk in pd.read_csv(path, chunksize=8192):
        X = torch.from_numpy(chunk[FEATS].to_numpy(dtype=np.float32))
        with torch.no_grad():
            p1 = NF.softmax(model(X), dim=1)[:, 1].double().tolist()
        for b, v in zip(chunk["bag_id"].to_numpy(), p1):
            b = int(b)
            if b not in sums:
                sums[b] = 0.0
                counts[b] = 0
                order.append(b)
            sums[b] += v
            counts[b] += 1
    return ["%.4f" % (sums[b] / counts[b]) for b in order]


def scores_match(got_text, ref_lines):
    """Parse got (one score per line) against ref with per-line tolerance."""
    lines = [l for l in got_text.splitlines() if l.strip() != ""]
    if len(lines) != len(ref_lines):
        return False, "lines got=%d want=%d" % (len(lines), len(ref_lines))
    for i, (g, r) in enumerate(zip(lines, ref_lines)):
        try:
            gv, rv = float(g), float(r)
        except ValueError:
            return False, "line %d unparsable: %r" % (i, g)
        if abs(gv - rv) > TOL:
            return False, "line %d got=%.6f want=%s" % (i, gv, r)
    return True, "%d lines" % len(lines)


def run_scorer(bag, out):
    if os.path.exists(out):
        os.remove(out)
    return subprocess.run(["python3", SCORER, bag, out],
                          capture_output=True, text=True, timeout=280)


def case_ok(model, bag, label):
    ref = _try(lambda: bag_reference(model, bag), None)
    if not isinstance(ref, list):
        check(label + ": reference recompute", False, str(ref))
        return
    r = run_scorer(bag, "/tmp/case_out.txt")
    ok = r.returncode == 0 and os.path.isfile("/tmp/case_out.txt")
    got = _try(lambda: open("/tmp/case_out.txt").read(), "") if ok else ""
    m, d = _try(lambda: scores_match(got, ref), (False, "parse error"))
    same = (r.stdout == got)
    check(label + ": scores match recompute", ok and m,
          "rc=%d %s" % (r.returncode, d if isinstance(d, str) else ""))
    check(label + ": stdout == output file", same)


def _write_stress(path):
    n = STRESS_ROWS - (STRESS_ROWS % STRESS_BAGS)
    rng = np.random.default_rng(5300)
    bg = np.repeat(np.arange(STRESS_BAGS), n // STRESS_BAGS)
    feats = rng.uniform(-1.0, 1.0, (n, F))
    df = pd.DataFrame(feats, columns=FEATS)
    df.insert(0, "bag_id", bg)
    df.round(6).to_csv(path, index=False)
    return True


def main():
    check("frozen triage model present + correct shape",
          os.path.isfile(MODEL) and
          bool(_try(lambda: arch_ok(torch.load(MODEL, map_location="cpu")), False)))

    check("exists /app/bag_mean.py", os.path.isfile(SCORER))
    check("exists /app/bag_means.txt", os.path.isfile(ART))

    model = _try(load_model, None)

    if model is not None and os.path.isfile(SCORER) and os.path.isfile(VISIBLE):
        # ---- visible artifact + visible re-execution ----
        ref = _try(lambda: bag_reference(model, VISIBLE), None)
        art = _try(lambda: open(ART).read(), "")
        m, d = _try(lambda: scores_match(art, ref), (False, "parse error"))
        check("bag_means.txt matches recompute (8 bags)", bool(m), str(d))
        case_ok(model, VISIBLE, "visible rerun")

        # ---- hidden bags ----
        if os.path.isdir(HIDDEN):
            bags = sorted(f for f in os.listdir(HIDDEN) if f.endswith(".csv"))
            check("hidden bags present", len(bags) >= 2, str(bags))
            for b in bags:
                case_ok(model, os.path.join(HIDDEN, b), "hidden '%s'" % b)
        else:
            check("hidden bags directory present", False)

        # ---- edges ----
        pd.DataFrame(columns=["bag_id"] + FEATS).to_csv("/tmp/empty_bag.csv", index=False)
        r = run_scorer("/tmp/empty_bag.csv", "/tmp/empty_out.txt")
        eout = _try(lambda: open("/tmp/empty_out.txt").read(), "<missing>")
        check("header-only bag -> empty outputs, exit 0",
              r.returncode == 0 and r.stdout == "" and eout == "",
              "rc=%d" % r.returncode)

        # (a) bag_id + x0..x18 only: feature column x19 missing
        nocol = pd.DataFrame({c: [0.5, 0.5] for c in FEATS[:-1]})
        nocol.insert(0, "bag_id", [7, 7])
        nocol.to_csv("/tmp/nocol.csv", index=False)
        r1 = run_scorer("/tmp/nocol.csv", "/tmp/nocol_out.txt")
        check("missing feature columns -> exit non-zero", r1.returncode != 0,
              "rc=%d" % r1.returncode)

        # (b) non-numeric feature value, written as raw CSV text
        row = ",".join(["0.1"] * F)
        with open("/tmp/nonnum.csv", "w") as fh:
            fh.write("bag_id," + ",".join(FEATS) + "\n")
            fh.write("3,abc," + ",".join(["0.1"] * (F - 1)) + "\n")
            fh.write("4," + row + "\n")
        r2 = run_scorer("/tmp/nonnum.csv", "/tmp/nonnum_out.txt")
        check("non-numeric feature -> exit non-zero", r2.returncode != 0,
              "rc=%d" % r2.returncode)

        # ---- stress bag: bounded RSS + deadline + correctness ----
        stress = "/tmp/stress_bag.csv"
        sgen = _try(lambda: _write_stress(stress), False)
        if sgen:
            p = subprocess.run(["python3", "/tests/bag_wrap.py", stress,
                                "/tmp/stress_out.txt", SCORER],
                               capture_output=True, text=True, timeout=280)
            rc, peak, dt = -1, 0, -1.0
            for line in p.stdout.splitlines():
                parts = line.split()
                if len(parts) == 4 and parts[0] == "MEAS":
                    rc, peak, dt = int(parts[1]), int(parts[2]), float(parts[3])
            sref = _try(lambda: bag_reference(model, stress), None)
            sgot = _try(lambda: open("/tmp/stress_out.txt").read(), "") \
                if os.path.isfile("/tmp/stress_out.txt") else ""
            sm, sd = _try(lambda: scores_match(sgot, sref), (False, "parse error"))
            check("stress bag finished", rc == 0, "rc=%d" % rc)
            check("stress bag memory bounded (<= 400MB)", 0 < peak <= RSS_CAP_KB,
                  "peak=%dKB cap=%dKB" % (peak, RSS_CAP_KB))
            check("stress bag within deadline (<= 120s)", 0 <= dt <= TIME_MAX_S,
                  "%.1fs" % dt)
            check("stress bag scores match recompute", bool(sm), str(sd))
        else:
            check("stress bag generated", False)

    failed = sum(1 for _, ok in CHECKS if not ok)
    print("TOTAL %d FAILED %d" % (len(CHECKS), failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(1)
