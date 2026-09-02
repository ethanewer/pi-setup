#!/usr/bin/env python3
"""Independent verifier helper for tasks/amber-helix.

Each sub-command tests one facet of the executed deliverables.  A facet passes
when every assertion inside it holds; the helper exits 0 iff the named facet
passed, 1 otherwise.  test.sh drives these facets and turns the aggregate
pass/fail count into /logs/verifier/reward.txt.

All checks are re-derived from the *documented* contract rather than from any
oracle implementation: the catalog match set, the primer Tm/orientation rules,
and the held-out Spearman correlations are recomputed (or re-run) here with this
helper's own logic.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys

import numpy as np
from scipy.stats import spearmanr

APP = "/app"
HID = "/tests/hidden"
COMP = {"A": "T", "T": "A", "C": "G", "G": "C"}
THRESH = 0.9


def fail(msg: str) -> int:
    print("  [fail] %s" % msg, file=sys.stderr)
    return 1


def ok() -> int:
    return 0


def _run(app, args):
    r = subprocess.run([sys.executable, app] + args, capture_output=True, text=True)
    return r.returncode, r.stdout, r.stderr


def _load_npy(p):
    a = np.load(p)
    if np.any(np.isnan(a)) or np.any(np.isinf(a)):
        raise ValueError("non-finite vector in %s" % p)
    return a


# ------------------------------------------------------------------ catalog
def _expected_matches(catalog_path, names_path, limit=None):
    with open(catalog_path, "rb") as fh:
        catalog = json.load(fh)
    with open(names_path, "rb") as fh:
        wanted = {n.strip().lower() for n in fh.read().decode().splitlines()
                  if n.strip()}
    out = []
    for e in catalog:
        name = e.get("name") if isinstance(e, dict) else None
        if isinstance(name, str) and name.strip() and name.strip().lower() in wanted:
            out.append(e)
            if limit is not None and len(out) >= limit:
                break
    return out


def cat_visible():
    if not os.path.exists("/app/load_catalog.py"):
        return fail("missing deliverable load_catalog.py")
    if not os.path.exists("/app/filtered_catalog.json"):
        return fail("missing deliverable filtered_catalog.json")
    expected = _expected_matches("/app/catalog.json", "/app/wanted_names.txt")
    if not expected:
        return fail("no expected matches computed for default catalog")
    emitted = json.load(open("/app/filtered_catalog.json"))
    if [m["id"] for m in emitted] != [m["id"] for m in expected]:
        return fail("filtered_catalog.json wrong:\n got %s\nwant %s" % (
            [m["id"] for m in emitted], [m["id"] for m in expected]))
    rc, _, err = _run("/app/load_catalog.py", [
        "--catalog", "/app/catalog.json",
        "--names", "/app/wanted_names.txt",
        "--limit", "1000", "--out", "/tmp/tel_cat.json"])
    if rc != 0:
        return fail("catalog re-run rc=%s %s" % (rc, err.strip()))
    if json.load(open("/tmp/tel_cat.json")) != expected:
        return fail("catalog re-run disagrees with expected matches")
    return ok()


def cat_hidden():
    cp = os.path.join(HID, "catalog", "catalog.json")
    npth = os.path.join(HID, "catalog", "names.txt")
    expected = _expected_matches(cp, npth)
    if not expected:
        return fail("hidden catalog should have matches")
    # the hidden catalog has an entry missing a 'name', trailing-space names
    rc, _, err = _run("/app/load_catalog.py", [
        "--catalog", cp, "--names", npth, "--limit", "1000",
        "--out", "/tmp/t_cat_h.json"])
    if rc != 0:
        return fail("hidden catalog run rc=%s %s" % (rc, err.strip()))
    got = json.load(open("/tmp/t_cat_h.json"))
    if [m["id"] for m in got] != [m["id"] for m in expected]:
        return fail("hidden catalog mismatch got=%s want=%s" % (
            [m["id"] for m in got], [m["id"] for m in expected]))
    return ok()


def cat_edge():
    cp = os.path.join(HID, "catalog", "catalog.json")
    # (a) empty names -> empty list, exit 0
    rc, _, _ = _run("/app/load_catalog.py", [
        "--catalog", cp,
        "--names", os.path.join(HID, "catalog", "names_empty.txt"),
        "--limit", "1000", "--out", "/tmp/t_cat_empty.json"])
    if rc != 0 or json.load(open("/tmp/t_cat_empty.json")) != []:
        return fail("empty names file should yield an empty list")
    # (b) limit=1 truncates to first match (names are case-mixed)
    ones = os.path.join(HID, "catalog", "names_one.txt")
    rc, _, _ = _run("/app/load_catalog.py", [
        "--catalog", cp, "--names", ones, "--limit", "1",
        "--out", "/tmp/t_cat_one.json"])
    if rc != 0:
        return fail("limit=1 run failed")
    exp1 = _expected_matches(cp, ones, limit=1)
    got = json.load(open("/tmp/t_cat_one.json"))
    if [m["id"] for m in got] != [m["id"] for m in exp1]:
        return fail("limit=1 should keep exactly first match (got %s)" % (
            [m["id"] for m in got]))
    # (c) trailing-comma malformed catalog must return nonzero
    bad = "/tmp/t_bad_cat.json"
    with open(bad, "w") as fh:
        fh.write('[{"id":"x","name":"A"}, {"id":"y","name":"B"},]')
    rc, _, _ = _run("/app/load_catalog.py", [
        "--catalog", bad, "--names", "/app/wanted_names.txt",
        "--limit", "1000", "--out", "/tmp/t_cat_bad.json"])
    if rc == 0:
        return fail("malformed catalog must return nonzero exit")
    return ok()


# ------------------------------------------------------------------ primers
def read_template(path):
    seq = []
    for line in open(path):
        line = line.strip()
        if line.startswith(">"):
            if seq:
                break
            continue
        if line:
            seq.append("".join(ch for ch in line if ch != " "))
    return "".join(seq).upper()


def reverse_complement(s):
    return "".join(COMP[c] for c in reversed(s))


def wallace(s):
    if not s:
        return 0.0
    return 2.0 * (s.count("A") + s.count("T")) + 4.0 * (s.count("G") + s.count("C"))


def validate_primers(res, scene, seq):
    if res.get("error"):
        return "design reported error: %s" % res["error"]
    loc = scene["locus"]
    start, end = int(loc["start"]), int(loc["end"])
    mutant = scene["mutant"].upper().strip()
    amin = int(scene["anneal_length"]["min"])
    amax = int(scene["anneal_length"]["max"])
    tmin = float(scene["tm"]["min"])
    tmax = float(scene["tm"]["max"])

    f = res.get("forward")
    r = res.get("reverse")
    if not f or not r:
        return "primer pair missing"
    lf = f["anneal_length"]
    if not (amin <= lf <= amax):
        return "forward anneal_length out of bounds"
    expect_fregion = seq[start - 1 - lf: start - 1]
    if f["anneal_region"] != expect_fregion:
        return "forward anneal region does not bind upstream locus"
    if f["seq"] != expect_fregion + mutant:
        return "forward sequence structure wrong"
    if not f["seq"].endswith(mutant):
        return "forward does not encode the mutant at its 3' end"
    tf = wallace(expect_fregion)
    if not (tmin <= tf <= tmax):
        return "forward tm out of bounds"
    if abs(f["tm"] - round(tf, 2)) > 0.011:
        return "forward tm not recomputed from anneal region"

    lr = r["anneal_length"]
    if not (amin <= lr <= amax):
        return "reverse anneal_length out of bounds"
    expect_rregion = reverse_complement(seq[end: end + lr])

    if r["anneal_region"] != expect_rregion:
        return "reverse anneal region wrong"
    if r["seq"] != expect_rregion + reverse_complement(mutant):
        return "reverse sequence structure wrong"
    if not r["seq"].endswith(reverse_complement(mutant)):
        return "reverse does not encode rc-mutant at 3' end"
    tr = wallace(expect_rregion)
    if not (tmin <= tr <= tmax):
        return "reverse tm out of bounds"
    if abs(r["tm"] - round(tr, 2)) > 0.011:
        return "reverse tm not recalculated from anneal region"
    return None


def pri_visible():
    for f in ("/app/design_primers.py", "/app/primers.json",
              "/app/mutation_scene.json", "/app/target.fasta"):
        if not os.path.exists(f):
            return fail("missing %s" % f)
    scene = json.load(open("/app/mutation_scene.json"))
    seq = read_template("/app/target.fasta")
    res = json.load(open("/app/primers.json"))
    err = validate_primers(res, scene, seq)
    if err:
        return fail("deliverable primers invalid: %s" % err)
    rc, _, errs = _run("/app/design_primers.py", [
        "--scene", "/app/mutation_scene.json", "--out", "/tmp/t_primer.json"])
    if rc != 0:
        return fail("primers re-run failed: %s" % errs.strip())
    rerun = json.load(open("/tmp/t_primer.json"))
    if rerun.get("forward", {}).get("seq") != res["forward"]["seq"] or \
       rerun.get("reverse", {}).get("seq") != res["reverse"]["seq"]:
        return fail("primers re-run disagrees with deliverable")
    return ok()


def pri_hidden():
    sp = os.path.join(HID, "primers", "scene.json")
    tp = os.path.join(HID, "primers", "target.fasta")
    scene = json.load(open(sp))
    seq = read_template(tp)
    rc, _, err = _run("/app/design_primers.py", [
        "--scene", sp, "--out", "/tmp/t_primer_h.json"])
    if rc != 0:
        return fail("hidden primers run failed: %s" % err.strip())
    res = json.load(open("/tmp/t_primer_h.json"))
    verr = validate_primers(res, scene, seq)
    if verr:
        return fail("hidden primer design invalid: %s" % verr)
    return ok()


def pri_edge():
    sp = os.path.join(HID, "primers", "close_scene.json")
    rc, _, _ = _run("/app/design_primers.py", [
        "--scene", sp, "--out", "/tmp/t_prim_close.json"])
    if rc != 0:
        return fail("close-scene should still write a JSON report")
    if "insufficient-upstream" not in str(
            json.load(open("/tmp/t_prim_close.json")).get("error")):
        return fail("expected insufficient-upstream error")

    rc, _, _ = _run("/app/design_primers.py", [
        "--scene", os.path.join(HID, "primers", "bad_scene.json"),
        "--out", "/tmp/t_prim_bad.json"])
    if rc != 0:
        return fail("bad-scene should still write a JSON report")
    if "non-standard-nucleotide" not in str(
            json.load(open("/tmp/t_prim_bad.json")).get("error")):
        return fail("expected non-standard-nucleotide error")

    tp = os.path.join(HID, "primers", "target.fasta")
    mm = {"template": tp, "locus": {"start": 210, "end": 212}, "mutant": "GT",
          "anneal_length": {"min": 19, "max": 25},
          "tm": {"min": 56.0, "max": 63.0}}
    json.dump(mm, open("/tmp/t_mm.json", "w"))
    rc, _, _ = _run("/app/design_primers.py", [
        "--scene", "/tmp/t_mm.json", "--out", "/tmp/t_prim_mm.json"])
    if rc != 0:
        return fail("length-mismatch should still write a JSON report")
    if "length-mismatch" not in str(
            json.load(open("/tmp/t_prim_mm.json")).get("error")):
        return fail("expected length-mismatch error")
    return ok()


# ---------------------------------------------------------------- affinity
def check_report(report, X, y, label):
    if report.get("n_seeds") != 8:
        return fail("%s: expected n_seeds=8, got %r" % (label, report.get("n_seeds")))
    n = X.shape[0]
    allids = {}
    for row in report["seeds"]:
        ids = [int(i) for i in row["test_ids"]]
        if len(ids) < 2:
            return fail("%s: too few test rows" % label)
        if len(set(ids)) != len(ids):
            return fail("%s: duplicate test_ids" % label)
        frac = len(ids) / float(n)
        if not (0.1 <= frac <= 0.3):
            return fail("%s: test fraction %.2f outside holdout band" % (label, frac))
        if not all(0 <= i < n for i in ids):
            return fail("%s: test id out of range" % label)
        pred = [float(v) for v in row["test_pred"]]
        if len(pred) != len(ids):
            return fail("%s: test_pred length mismatch" % label)
        sp = spearmanr(y[ids], pred).correlation
        if sp is None or sp < THRESH:
            return fail("%s: seed %s spearman %.3f < %s" % (label, row["seed"], sp, THRESH))
        allids.setdefault(row["seed"], tuple(sorted(ids)))
    if len(allids) != report["n_seeds"]:
        return fail("%s: seed keys not distinct" % label)
    diffs = {allids[k] for k in allids}
    if len(diffs) < report["n_seeds"] * 0.75:
        return fail("%s: holdouts overlap too much across seeds" % label)
    return None


def affinity_visible():
    for f in ("/app/train_affinity.py", "/app/affinity_report.json",
              "/app/affinity_descriptors.npy", "/app/affinity_measurements.npy"):
        if not os.path.exists(f):
            return fail("missing %s" % f)
    X = _load_npy("/app/affinity_descriptors.npy")
    y = _load_npy("/app/affinity_measurements.npy")
    rep = json.load(open("/app/affinity_report.json"))
    err = check_report(rep, X, y, "app")
    if err:
        return fail(err)
    rc, _, errs = _run("/app/train_affinity.py", [
        "--descriptors", "/app/affinity_descriptors.npy",
        "--targets", "/app/affinity_measurements.npy",
        "--n_seeds", "8", "--out", "/tmp/t_aff_app.json"])
    if rc != 0:
        return fail("affinity default re-run failed: %s" % errs.strip())
    if not json.load(open("/tmp/t_aff_app.json")).get("all_pass"):
        return fail("affinity default re-run below threshold")
    return ok()


def affinity_hidden():
    Xp = os.path.join(HID, "affinity", "descriptors.npy")
    yp = os.path.join(HID, "affinity", "measurements.npy")
    X = _load_npy(Xp)
    y = _load_npy(yp)
    if X.shape[1] != 12:
        return fail("hidden descriptors wrong width")
    rc, _, errs = _run("/app/train_affinity.py", [
        "--descriptors", Xp, "--targets", yp,
        "--n_seeds", "8", "--out", "/tmp/t_aff_h.json"])
    if rc != 0:
        return fail("hidden affinity run failed: %s" % errs.strip())
    err = check_report(json.load(open("/tmp/t_aff_h.json")), X, y, "hidden")
    if err:
        return fail(err)
    return ok()


def affinity_edge():
    # malformed shape -> nonzero exit, no crash
    rc, _, errs = _run("/app/train_affinity.py", [
        "--descriptors", os.path.join(HID, "affinity", "shape_bad_descriptors.npy"),
        "--targets", os.path.join(HID, "affinity", "shape_bad_measurements.npy"),
        "--n_seeds", "2", "--out", "/tmp/t_aff_shape.json"])
    if rc == 0:
        return fail("shape-mismatch must return nonzero exit (rc=%s %s)" % (rc, errs.strip()))
    # tiny-but-valid dataset must still emit a valid report
    X = np.random.default_rng(1).normal(size=(20, 12))
    y = np.asarray([float(i) for i in range(20)])
    np.save("/tmp/t_tinyX.npy", X)
    np.save("/tmp/t_tinyY.npy", y)
    rc, _, errs = _run("/app/train_affinity.py", [
        "--descriptors", "/tmp/t_tinyX.npy", "--targets", "/tmp/t_tinyY.npy",
        "--n_seeds", "2", "--out", "/tmp/t_aff_tiny.json"])
    if rc != 0:
        return fail("tiny dataset should not crash (rc=%d %s)" % (rc, errs.strip()))
    if not json.load(open("/tmp/t_aff_tiny.json")).get("seeds"):
        return fail("tiny run produced no seed results")
    return ok()


SCEN = {
    "catalog-visible": cat_visible,
    "catalog-hidden": cat_hidden,
    "catalog-edge": cat_edge,
    "primers-visible": pri_visible,
    "primers-hidden": pri_hidden,
    "primers-edge": pri_edge,
    "affinity-visible": affinity_visible,
    "affinity-hidden": affinity_hidden,
    "affinity-edge": affinity_edge,
}


def main(argv):
    if not argv:
        print("usage: verify_helper.py <scenario>", file=sys.stderr)
        return 2
    name = argv[0]
    if name not in SCEN:
        print("unknown scenario %s" % name, file=sys.stderr)
        return 2
    sys.exit(SCEN[name]())


if __name__ == "__main__":
    main(sys.argv[1:])