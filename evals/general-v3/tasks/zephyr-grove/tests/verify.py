#!/usr/bin/env python3
"""Independent verifier for zephyr-grove.

Recomputes the expected answer.txt, the grid.txt Latin-square property, and the
plans.txt overlap result directly from each config (independent of the solver's
implementation style), then:
  * checks the committed /app deliverables against the shipped /app/config.json,
  * re-runs /app/solver.py on the visible config and on each hidden config.

Writes the reward via tests/test.sh (that script owns /logs). Exits 0 only if
every check passes.
"""
import json
import os
import shutil
import subprocess
import sys

SOLVER = "/app/solver.py"
VISIBLE_CONFIG = "/app/config.json"
HIDDEN_ROOT = "/tests/hidden"

failures = []


def fail(message):
    failures.append(message)


def check(cond, message):
    if not cond:
        fail(message)


# ---------------------------------------------------------------- gold logic
def gold_answer_count(allowed, target):
    target = int(target)
    if target < 0:
        return "0"
    vals = [int(a) for a in allowed if isinstance(a, (int, float)) and int(a) > 0]
    dp = [0] * (target + 1)
    dp[0] = 1
    for a in vals:
        for s in range(target, a - 1, -1):
            dp[s] += dp[s - a]
    return str(dp[target])


def hhmm(minute):
    minute = max(0, min(int(minute), 1439))
    return "%02d:%02d" % (minute // 60, minute % 60)


def gold_plans(cfg):
    bstart = int(cfg.get("business_start", 540))
    bend = int(cfg.get("business_end", 1020))
    lstart = int(cfg.get("lunch_start", 720))
    lend = int(cfg.get("lunch_end", 780))
    dur = int(cfg.get("duration_needed", 30))
    busy = cfg.get("busy", {}) or {}
    intervals = []
    for _p, segs in busy.items():
        if not isinstance(segs, list):
            continue
        for seg in segs:
            if not isinstance(seg, (list, tuple)) or len(seg) < 2:
                continue
            try:
                s, e = int(seg[0]), int(seg[1])
            except (TypeError, ValueError):
                continue
            if e > s:
                intervals.append((s, e))

    def free(m):
        if m < bstart or m >= bend or (lstart <= m < lend):
            return False
        return not any(a <= m < bb for (a, bb) in intervals)

    runs = []
    start = None
    for m in range(bstart, bend):
        if free(m):
            start = m if start is None else start
        else:
            if start is not None and m - start >= dur:
                runs.append((start, m))
            start = None
    if start is not None and bend - start >= dur:
        runs.append((start, bend))

    windows = [{"start": hhmm(s), "end": hhmm(e)} for (s, e) in runs]
    return {
        "business": {"start": hhmm(bstart), "end": hhmm(bend)},
        "lunch": {"start": hhmm(lstart), "end": hhmm(lend)},
        "duration_needed": dur,
        "windows": windows,
    }


# ------------------------------------------------------------- helper checks
def check_grid(gpath):
    """Return None if gpath is a valid 9x9 two-digit zero-padded Latin square."""
    try:
        with open(gpath) as fh:
            lines = [ln.strip() for ln in fh if ln.strip()]
    except OSError:
        return "grid.txt unreadable"
    if len(lines) != 9:
        return "grid.txt does not have exactly 9 rows"
    m = []
    for ln in lines:
        toks = ln.split()
        if len(toks) != 9:
            return "a grid row does not have 9 tokens"
        row = []
        for t in toks:
            if len(t) != 2 or not t.isdigit():
                return "grid token is not a two-digit number: %r" % t
            v = int(t)
            if not (1 <= v <= 9):
                return "grid token out of range 1..9: %r" % t
            row.append(v)
        m.append(row)
    for row in m:
        if sorted(row) != list(range(1, 10)):
            return "grid row is not a permutation of 1..9"
    for c in range(9):
        if sorted(m[r][c] for r in range(9)) != list(range(1, 10)):
            return "grid column is not a permutation of 1..9"
    return None


def run_solver(config, outdir):
    shutil.rmtree(outdir, ignore_errors=True)
    os.makedirs(outdir, exist_ok=True)
    proc = subprocess.run(
        [sys.executable, SOLVER, config, outdir], capture_output=True, text=True
    )
    return proc.returncode == 0


def validate_outputs(cfg, outdir, label):
    gold_answer = gold_answer_count(cfg.get("allowed", []), cfg.get("target_sum", 0))
    a_path = os.path.join(outdir, "answer.txt")
    g_path = os.path.join(outdir, "grid.txt")
    p_path = os.path.join(outdir, "plans.txt")

    check(os.path.exists(a_path), "%s: missing answer.txt" % label)
    check(os.path.exists(g_path), "%s: missing grid.txt" % label)
    check(os.path.exists(p_path), "%s: missing plans.txt" % label)

    if os.path.exists(a_path):
        with open(a_path, "rb") as fh:
            raw = fh.read()
        if raw.endswith(b"\n"):
            fail("%s: answer.txt has a trailing newline" % label)
        if raw.decode() != gold_answer:
            fail("%s: answer.txt is %r, expected %r" % (label, raw.decode(), gold_answer))

    if os.path.exists(g_path):
        err = check_grid(g_path)
        if err:
            fail("%s: grid.txt -> %s" % (label, err))

    if os.path.exists(p_path):
        try:
            got = json.load(open(p_path))
        except Exception as exc:
            fail("%s: plans.txt not valid JSON (%s)" % (label, exc))
            got = None
        if got is not None and got != gold_plans(cfg):
            fail("%s: plans.txt mismatch (got %s, want %s)"
                 % (label, json.dumps(got), json.dumps(gold_plans(cfg))))


def gold_answer_for(cfg_allowed, target):
    # pushes through gold_answer_count but returns int form; kept for clarity
    return gold_answer_count(cfg_allowed, target)


# ------------------------------------------------------------- run everything
cases = []
if os.path.isdir(HIDDEN_ROOT):
    cases = sorted(d for d in os.listdir(HIDDEN_ROOT)
                   if os.path.isdir(os.path.join(HIDDEN_ROOT, d)))
check(len(cases) >= 2, "expected at least 2 hidden case directories")

# visible case
cfg_vis = json.load(open(VISIBLE_CONFIG))
ok = run_solver(VISIBLE_CONFIG, "/tmp/visout")
check(ok, "visible: /app/solver.py failed to run")
if ok:
    validate_outputs(cfg_vis, "/tmp/visout", "visible")

# hidden cases
for case in cases:
    cpath = os.path.join(HIDDEN_ROOT, case, "config.json")
    cfg = json.load(open(cpath))
    outdir = "/tmp/hidden/%s" % case
    ok = run_solver(cpath, outdir)
    check(ok, "hidden/%s: /app/solver.py failed to run" % case)
    if ok:
        validate_outputs(cfg, outdir, "hidden/%s" % case)

# --- committed /app deliverables (the literal paths the verifier must check)
vis = json.load(open("/app/config.json")) if os.path.exists("/app/config.json") else {}
check(os.path.exists(SOLVER), "missing deliverable /app/solver.py")
check(os.path.exists("/app/answer.txt"), "missing deliverable /app/answer.txt")
check(os.path.exists("/app/grid.txt"), "missing deliverable /app/grid.txt")
check(os.path.exists("/app/plans.txt"), "missing deliverable /app/plans.txt")
if os.path.exists("/app/answer.txt"):
    # answer.txt: exact bytes, no trailing newline
    with open("/app/answer.txt", "rb") as fh:
        raw = fh.read()
    check(raw.endswith(b"\n") is False, "deliverable /app/answer.txt has trailing newline")
    check(raw.decode() == gold_answer_for(vis.get("allowed", []), vis.get("target_sum", 0)),
          "deliverable /app/answer.txt wrong value")
if os.path.exists("/app/grid.txt"):
    err = check_grid("/app/grid.txt")
    if err:
        fail("deliverable /app/grid.txt -> %s" % err)
plans_committed = None
if os.path.exists("/app/plans.txt"):
    try:
        plans_committed = json.load(open("/app/plans.txt"))
    except Exception as exc:
        fail("deliverable /app/plans.txt not valid JSON (%s)" % exc)
if plans_committed is not None and plans_committed != gold_plans(vis):
    fail("deliverable /app/plans.txt mismatch")
# solver must be deterministic/repeatable: a fresh run equals committed files
if os.path.exists(SOLVER):
    proc = subprocess.run([sys.executable, SOLVER, "/app/config.json", "/tmp/commit"],
                          capture_output=True, text=True)
    if proc.returncode != 0:
        fail("re-running /app/solver.py on the visible config failed")
    else:
        for name in ("answer.txt", "grid.txt", "plans.txt"):
            a = os.path.join("/app", name)
            b = os.path.join("/tmp/commit", name)
            if os.path.exists(a) and os.path.exists(b):
                check(open(a, "rb").read() == open(b, "rb").read(),
                      "deliverable /app/%s differs from a fresh solver run" % name)
            else:
                check(os.path.exists(a) and os.path.exists(b),
                      "deliverable /app/%s or re-run output missing" % name)

if failures:
    print("FAILURES:")
    for m in failures:
        print("  - " + m)
    sys.exit(1)
print("ALL PASS")
sys.exit(0)