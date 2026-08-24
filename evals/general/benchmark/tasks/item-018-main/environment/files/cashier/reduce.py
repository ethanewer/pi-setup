#!/usr/bin/env python3
"""reduce.py — find the smallest failing prefix.

Simulates the CORRECT ledger (rowid -> balance) and runs the release build on
every prefix of the op file, reporting the shortest prefix whose stdout differs
from the correct simulation. Pass --debug to use the debug binary instead.

Usage:
    python3 reduce.py [casefile]
"""
import subprocess
import sys
import tempfile
import os

CASE = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else "cases.txt"
BIN = "build/release/cashier"
if "--debug" in sys.argv:
    BIN = "build/debug/cashier"

lines = [ln for ln in open(CASE).read().splitlines() if ln.strip()]


def reference(output_lines):
    """Correct rowid-ledger simulation."""
    rows = {}
    out = []
    for ln in output_lines:
        t = ln.split()
        if not t:
            continue
        op = t[0]
        if op == "N":
            r = int(t[1])
            rows.setdefault(r, [0, b"\x00" * 16])
        elif op == "W":
            r, v = int(t[1]), int(t[2])
            if r in rows:
                rows[r][0] += v
        elif op == "F":
            rows.pop(int(t[1]), None)
        elif op == "S":
            out.append(str(sum(v[0] for v in rows.values())))
        elif op == "T":
            r = int(t[1])
            if r in rows:
                bal, tag = rows[r]
                out.append("%d %s" % (bal, tag.hex()))
    out.append("LIVE %d/16" % len(rows))
    return out


def run(prefix):
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as f:
        f.write("\n".join(prefix) + "\n")
        tmp = f.name
    try:
        p = subprocess.run([BIN, "--input", tmp], capture_output=True, text=True)
        return p.returncode, p.stdout.splitlines()
    finally:
        os.unlink(tmp)


bad = 0
for i in range(2, len(lines) + 1):
    prefix = lines[:i]
    rc, got = run(prefix)
    want = reference(prefix)
    if rc != 0 or got != want:
        bad += 1
        print("first failing prefix length = %d (exit=%d)" % (i, rc))
        for ln in prefix:
            print("    op: %s" % ln)
        if rc != 0:
            print("    program exited non-zero")
        else:
            print("    got:  %s" % got)
            print("    want: %s" % want)
        break

if not bad:
    print("no failing prefix found (len=%d)" % len(lines))