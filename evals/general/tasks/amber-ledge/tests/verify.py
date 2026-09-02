#!/usr/bin/env python3
"""amber-ledge verifier.

Executes every /app deliverable on the hidden cases under /tests/hidden and
checks the results against the stored expected answers. Exits 0 iff every
check passes, else 1. This is the real work behind tests/test.sh.
"""
import json
import os
import subprocess
import sys
import tempfile

H = "/tests/hidden"
APP = "/app"
fails = []
checks = 0


def run(cmd, err_ctx=""):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    except Exception as e:  # missing binary / file, timeout, etc.
        fails.append(err_ctx or "  ERR: %r %r" % (cmd, e))
        return None
    if r.returncode != 0:
        fails.append((err_ctx or " ".join(cmd)) + " rc=%d stderr=%s" % (r.returncode, r.stderr.strip()))
        return None
    return r.stdout


# `load` runs a command, records a failure on any problem, and returns stdout
# (or None). Same behaviour as `run`; kept as a separate name for readability.
load = run


def main():
    global checks

    # ---------- Deliverable 1: game.js ----------
    game_cases = json.load(open(os.path.join(H, "game.json")))
    for c in game_cases:
        checks += 1
        fn = "/tmp/cell.json"
        with open(fn, "w") as fh:
            json.dump(c["cell"], fh)
        out = load(["node", "/app/game.js", fn],
                   "game %s" % c["id"])
        if out is None:
            continue
        got = out.strip()
        if got != c["expect"]:
            fails.append("game.%s got=%r want=%r" % (c["id"], got, c["expect"]))

    # ---------- Deliverable 2: chess.py ----------
    chess_cases = json.load(open(os.path.join(H, "chess.json")))
    for c in chess_cases:
        for sub, key in (("legal", "expect_legal"), ("mate", "expect_mate")):
            checks += 1
            out = load(["python3", "/app/chess.py", sub, c["fen"]],
                       "chess.%s.%s" % (c["id"], sub))
            if out is None:
                continue
            try:
                got = set(json.loads(out))
            except Exception:
                fails.append("chess.%s.%s bad json %r" % (c["id"], sub, out))
                continue
            want = set(c[key])
            if got != want:
                fails.append("chess.%s.%s got=%d want=%d" % (c["id"], sub, len(got), len(want)))

    # ---------- Deliverable 3: planner.py ----------
    planner_cases = json.load(open(os.path.join(H, "planner.json")))
    for c in planner_cases:
        checks += 1
        fn = "/tmp/pl_in.json"
        with open(fn, "w") as fh:
            json.dump(c["batch"], fh)
        out_fn = "/tmp/pl_out.json"
        out = load(["python3", "/app/planner.py", fn, out_fn],
                   "planner %s" % c["id"])
        if out is None:
            continue
        try:
            got = json.load(open(out_fn))
        except Exception:
            fails.append("planner.%s missing/shorts output" % c["id"])
            continue
        if got != c["expect"]:
            fails.append("planner.%s got=%r want=%r" % (c["id"], got, c["expect"]))

    # ---------- Deliverable 4: mahjong.py ----------
    checks += 1
    want = json.load(open(os.path.join(H, "mahjong_expected.json")))
    out = load(["python3", "/app/mahjong.py", os.path.join(H, "hands")],
               "mahjong dir")
    if out is None:
        pass
    else:
        try:
            got = json.loads(out)
        except Exception:
            failss = None
            fails.append("mahjong bad output %r" % out)
        else:
            if got != want:
                fails.append("mahjong got=%r want=%r" % (got, want))

    # ---------- Deliverable 5: serialize.py ----------
    checks += 1
    in_fn = os.path.join(H, "serialize_input.json")
    out_fn = "/tmp/ser_out.json"
    out = load(["python3", "/app/serialize.py", in_fn, out_fn],
               "serialize")
    want = json.load(open(os.path.join(H, "serialize_expected.json")))
    if out is not None:
        try:
            got = json.load(open(out_fn))
        except Exception:
            fails.append("serialize missing output")
        else:
            if got != want:
                fails.append("serialize got=%r want=%r" % (got, want))

    if fails:
        sys.stderr.write("FAILED:\n")
        for f in fails:
            sys.stderr.write("  - %s\n" % f)
        sys.stderr.write("checks run: %d\n" % checks)
        return 1
    sys.stderr.write("PASS all %d checks\n" % checks)
    return 0


if __name__ == "__main__":
    sys.exit(main())