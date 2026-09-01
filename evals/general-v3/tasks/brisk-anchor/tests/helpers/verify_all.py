#!/usr/bin/env python3
"""brisk-anchor verifier: checks every deliverable against expected values,
goldens, and hidden-case outputs prepared by tests/test.sh. Independent of the
oracle implementation (uses only the documented public formats + a fresh TF-IDF
recomputation). Exits 0 only if everything passes."""
import json, os, numbers, subprocess, sys

FAILS = []
def check(name, cond, detail=""):
    if not cond:
        FAILS.append(f"{name}: {detail}" if detail else name)

def eq(a, b):
    return a == b

def norm_map(m):
    out = {}
    for e in m:
        out[e["field"]] = (e["chunk"], round(float(e["score"]), 9))
    return out

# load visible expectation once
vexp = None
try:
    with open("/tests/visible_expected.json") as fh:
        vexp = json.load(fh)
except Exception as ex:
    check("load-visible-expected", False, repr(ex))

# ---------------- 1. OCR visible ----------
try:
    with open("/app/invoice-labels.json") as fh: labels = json.load(fh)
    with open("/app/reference_index.json") as fh: ref = json.load(fh)
except Exception as ex:
    labels, ref = None, None
    check("ocr-visible-load", False, repr(ex))
    ref = {}
if ref is not None:
    if labels is None:
        check("ocr-visible", False, "invoice-labels.json unreadable")
    else:
        check("ocr-visible", eq(labels, ref),
              f"{sorted(labels.items())} vs {sorted(ref.items())}")

# ---------------- 2. field-map visible (recomputed independently) ----------
try:
    import subprocess
    rp = subprocess.run(
        ["python3", "/tests/helpers/recompute_fieldmap.py", "/app/fields", "/app/chunks"],
        capture_output=True, text=True).stdout.splitlines()
    exp_map = json.loads(rp[0]); exp_stats = json.loads(rp[1])
    with open("/app/field-map.json") as fh: fm = json.load(fh)
    with open("/app/retrieval-stats.json") as fh: st = json.load(fh)
    check("fm-visible", norm_map(fm) == norm_map(exp_map),
          f"{norm_map(fm)} vs {norm_map(exp_map)}")
    check("fm-stats-visible", st == exp_stats, f"{st} != {exp_stats}")
except Exception as ex:
    check("fm-visible", False, repr(ex))

# ---------------- 3. chess visible ----------
def positions_to_dict(arr):
    return {e["file"]: (e["placement"], e["side"]) for e in arr}
try:
    with open("/app/positions.json") as fh: pos = json.load(fh)
    boards_exp = vexp["boards"] if vexp else []
    check("chess-visible", vexp is not None and positions_to_dict(pos) == positions_to_dict(boards_exp),
          f"{positions_to_dict(pos)} vs {positions_to_dict(boards_exp)}")
except Exception as ex:
    check("chess-visible", False, repr(ex))

# ---------------- 4. profiles visible ----------
try:
    with open("/app/profiles.json") as fh: prof = json.load(fh)
    if vexp is None:
        raise RuntimeError("no visible_expected")
    pexp = {e["doc"]: {k: e[k] for k in ("name","email","phone","zip")} for e in vexp["profiles"]}
    pgot = {e["doc"]: {k: e[k] for k in ("name","email","phone","zip")} for e in prof}
    check("profiles-visible", pgot == pexp, f"{pgot} vs {pexp}")
except Exception as ex:
    check("profiles-visible", False, repr(ex))

# ---------------- 5. hidden OCR --------------
def load(p):
    with open(p) as fh: return json.load(fh)
ocs = ["scan_a", "scan_b_edge"]
for s in ocs:
    try:
        got = load(f"/tmp/ocr_{s}.json")
        exp = load(f"/tests/hidden/ocr/{s}/labels.json")
        check(f"ocr-hidden-{s}", eq(got, exp), f"{sorted(got.items())} vs {sorted(exp.items())}")
    except Exception as ex:
        check(f"ocr-hidden-{s}", False, repr(ex))

# ---------------- 6. hidden field-map --------------
for s in ("set_a", "set_b"):
    try:
        with open(f"/tmp/fm_{s}.json") as fh: got = json.load(fh)
        with open(f"/tmp/st_{s}.json") as fh: st = json.load(fh)
        with open(f"/tests/hidden/fieldmap/{s}/map.expected.json") as fh:
            exp = json.load(fh)
        # field dirs (mounted) for structural count checks
        fd = f"/tests/hidden/fieldmap/{s}/fields"
        cd = f"/tests/hidden/fieldmap/{s}/chunks"
        x = norm_map(got) == norm_map(exp)
        check(f"fm-hidden-{s}", x, f"{norm_map(got)} vs {norm_map(exp)}")
        nf = len([n for n in os.listdir(fd) if n.endswith('.txt')])
        nc = len([n for n in os.listdir(cd) if n.endswith('.txt')])
        keys_ok = set(st["per_field"].keys()) == set(norm_map(got).keys())
        check(f"fm-stats-hidden-{s}", st["num_fields"] == nf and st["num_chunks"] == nc
              and keys_ok and isinstance(st["aggregate"]["mean_best_score"], numbers.Number)
              and isinstance(st["aggregate"]["median_best_score"], numbers.Number)
              and all(isinstance(v["best_score"], numbers.Number)
                      and v["candidate_count"] == nc for v in st["per_field"].values()),
              f"structure {st}")
    except Exception as ex:
        check(f"fm-hidden-{s}", False, repr(ex))

# ---------------- 7. hidden chess --------------
try:
    with open("/tmp/chess_hidden.json") as fh: got = json.load(fh)
    with open("/tests/hidden/chess/positions.expected.json") as fh: exp = json.load(fh)
    check("chess-hidden", positions_to_dict(got) == positions_to_dict(list(exp.values())),
          f"{positions_to_dict(got)} vs {positions_to_dict(list(exp.values()))}")
except Exception as ex:
    check("chess-hidden", False, repr(ex))

# ---------------- 8. hidden profiles --------------
try:
    with open("/tmp/profiles_hidden.json") as fh: got = json.load(fh)
    with open("/tests/hidden/profiles/profiles.expected.json") as fh: exp = json.load(fh)
    g = {e["doc"]: {k: e[k] for k in ("name","email","phone","zip")} for e in got}
    x = {k: {kk: v[kk] for kk in ("name","email","phone","zip")} for k, v in exp.items()}
    check("profiles-hidden", g == x, f"{g} vs {x}")
except Exception as ex:
    check("profiles-hidden", False, repr(ex))

if FAILS:
    for f_ in FAILS:
        print("FAIL:", f_)
    sys.exit(1)
print("ALL CHECKS PASSED")
sys.exit(0)