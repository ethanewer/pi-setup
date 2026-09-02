#!/usr/bin/env python3
"""Graded verifier body for the gray-market task.

Reads the deliverable wheel (argv[1]) and a fresh set of hidden cases
(argv[2], JSON list of {input, expected, valid}). Runs with the isolated venv
interpreter, so the installed ``ledgercheck`` package is importable.

Prints a report and exits 0 only if every check passes.
"""
import json
import os
import re
import subprocess
import sys
import zipfile

import importlib.metadata

HIDDEN_CASES = sys.argv[2]
WHEEL = sys.argv[1]

cli = os.path.join(os.path.dirname(sys.executable), "ledger-check")
if not os.path.exists(cli):
    print("FAIL: no 'ledger-check' console script in the venv")
    sys.exit(1)

from ledgercheck import normalize_amount  # noqa: E402

fails = []

# ------------------------------- wheel metadata ------------------------------
wz = zipfile.ZipFile(WHEEL)
metadata = None
entry = None
for name in wz.namelist():
    if name.endswith(".dist-info/METADATA"):
        metadata = wz.read(name).decode("utf-8")
    elif name.endswith(".dist-info/entry_points.txt"):
        entry = wz.read(name).decode("utf-8")

if metadata is None:
    fails.append("wheel has no METADATA")
else:
    def field(key):
        m = re.search(r"^%s:\s*(.*)$" % key, metadata, re.M)
        return m.group(1).strip() if m else None

    if field("Name") != "ledger-check":
        fails.append("Name mismatch: %r" % field("Name"))
    if field("Version") != "0.4.2":
        fails.append("Version mismatch: %r" % field("Version"))
    deps = [d for d in re.findall(r"^Requires-Dist:.*$", metadata, re.M)]
    if deps:
        fails.append("unexpected runtime dependencies: %r" % deps)

if entry is None:
    fails.append("wheel has no entry_points.txt")
elif not re.search(r"ledger-check\s*=\s*ledgercheck\.cli:main", entry):
    fails.append("console-script entry 'ledger-check -> ledgercheck.cli:main' missing/wrong")

try:
    if importlib.metadata.version("ledger-check") != "0.4.2":
        fails.append("installed distribution version is not 0.4.2")
except Exception as exc:  # noqa: BLE001
    fails.append("installed distribution not importable via metadata: %r" % exc)

# --------------------------- functional / hidden cases ------------------------
def run_cli(text):
    data = (text + "\n").encode("utf-8")
    return subprocess.run([cli], input=data, capture_output=True)

cases = json.load(open(HIDDEN_CASES, encoding="utf-8"))
assert isinstance(cases, list) and cases, "hidden cases file must be a non-empty list"

for idx, case in enumerate(cases):
    inp = case["input"]
    tag = "case#%d %r" % (idx, inp)
    if case["valid"]:
        expected = case["expected"]
        try:
            got = normalize_amount(inp)
            if got != expected:
                fails.append("%s: normalize_amount returned %r, want %r" % (tag, got, expected))
        except Exception as exc:  # noqa: BLE001
            fails.append("%s: normalize_amount raised %r" % (tag, exc))

        r = run_cli(inp)
        if r.returncode != 0:
            fails.append("%s: ledger-check exited %d (stderr %r)" % (tag, r.returncode, r.stderr))
        elif r.stdout.decode().strip() != str(expected):
            fails.append("%s: ledger-check printed %r, want %r" % (tag, r.stdout.decode().strip(), str(expected)))
    else:
        try:
            normalize_amount(inp)
            fails.append("%s: normalize_amount accepted malformed input" % tag)
        except ValueError:
            pass
        except Exception as exc:  # noqa: BLE001
            fails.append("%s: normalize_amount raised wrong exception: %r" % (tag, exc))
        r = run_cli(inp)
        if r.returncode == 0:
            fails.append("%s: ledger-check accepted malformed input" % tag)

if fails:
    print("VERIFIER FAIL (%d problem(s)):" % len(fails))
    for f in fails:
        print("  -", f)
    sys.exit(1)

print("VERIFIER OK: metadata + %d hidden cases passed" % len(cases))
sys.exit(0)