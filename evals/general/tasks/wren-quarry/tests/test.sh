#!/bin/bash
# Verifier for wren-quarry: audits the fix-service state (/app/ops/state.json)
# for the attempt budget and per-line coverage, proves /app/pipeline/rectify.py
# was changed ONLY through the recorded fix requests (pristine hash chain),
# then EXECUTES the repaired deliverable module on hidden behavioural cases.
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import hashlib
import importlib.util
import json
import os
import sys

STATE = "/app/ops/state.json"
TARGET = "/app/pipeline/rectify.py"
PRISTINE = "/tests/pristine_rectify.py"
HIDDEN = "/tests/hidden"
BUDGET_LIMIT = 6          # grader ceiling on fix attempts (service budget is 8)
DEFECT_LINES = {14, 30, 37, 47, 58}

failures = []


def sha_bytes(data):
    return hashlib.sha256(data).hexdigest()


def eq(a, b):
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(eq(x, y) for x, y in zip(a, b))
    if isinstance(a, bool) or isinstance(b, bool):
        return a is b
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return abs(float(a) - float(b)) <= 1e-9
    return a == b


def load_json(path, label):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception as exc:
        failures.append("%s: unreadable (%r)" % (label, exc))
        return None


# ---------- 1. service state audit ----------
state = load_json(STATE, "ops/state.json")
try:
    target_bytes = open(TARGET, "rb").read()
except Exception as exc:
    print("target module unreadable: %r" % (exc,))
    target_bytes = None
    failures.append("rectify.py unreadable")

if state is not None and target_bytes is not None:
    try:
        pristine_bytes = open(PRISTINE, "rb").read()
    except Exception as exc:
        print("pristine copy missing: %r" % (exc,))
        sys.exit(1)
    if state.get("initial_sha256") != sha_bytes(pristine_bytes):
        failures.append("state initial_sha256 does not match the pristine module")
    if state.get("final_sha256") != sha_bytes(target_bytes):
        failures.append("state final_sha256 does not match the on-disk module "
                        "(direct edit or tampering detected)")

    used = state.get("fixes_used")
    if not isinstance(used, int) or isinstance(used, bool) or used < 0:
        failures.append("state fixes_used is not a sane integer")
    elif used > BUDGET_LIMIT:
        failures.append("too many fix attempts: fixes_used=%d > %d "
                        "(every POST /fix counts)" % (used, BUDGET_LIMIT))

    applied = state.get("applied")
    if not isinstance(applied, list):
        failures.append("state.applied missing")
        applied = []

    lines = pristine_bytes.decode("utf-8").split("\n")
    covered = set()
    for entry in applied:
        if not isinstance(entry, dict):
            failures.append("malformed applied entry")
            continue
        ln = entry.get("line")
        if not isinstance(ln, int) or isinstance(ln, bool) or not (1 <= ln <= len(lines)):
            failures.append("applied entry with invalid line %r" % (ln,))
            continue
        if ln not in DEFECT_LINES:
            failures.append("fix attempt spent on non-defect line %d" % ln)
        if lines[ln - 1] != entry.get("before"):
            failures.append("applied entry (line %d) does not chain from the "
                            "previous file state" % ln)
        lines[ln - 1] = entry.get("after")
        covered.add(ln)
    missing = DEFECT_LINES - covered
    if missing:
        failures.append("defect lines never repaired: %s" % sorted(missing))
    rebuilt = "\n".join(lines)
    if rebuilt != target_bytes.decode("utf-8"):
        failures.append("module content differs from the recorded fix chain "
                        "(file was edited outside the service)")

# ---------- 2. execute the deliverable module on hidden cases ----------
mod = None
if target_bytes is not None:
    try:
        spec = importlib.util.spec_from_file_location("rectify_verify", TARGET)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
    except Exception as exc:
        failures.append("rectify.py does not import/compile: %r" % exc)

if mod is not None:
    cases = sorted(os.listdir(HIDDEN)) if os.path.isdir(HIDDEN) else []
    if not cases:
        failures.append("no hidden cases present")
    for name in cases:
        path = os.path.join(HIDDEN, name)
        data = load_json(path, "hidden '%s'" % name)
        if not isinstance(data, dict) or not isinstance(data.get("cases"), list):
            if not failures or "unreadable" not in failures[-1]:
                failures.append("hidden '%s' malformed" % name)
            continue
        for i, case in enumerate(data["cases"]):
            fname = case.get("func")
            fn = getattr(mod, fname, None) if isinstance(fname, str) else None
            if fn is None or not callable(fn):
                failures.append("hidden '%s' case %d: unknown function %r" % (name, i, fname))
                continue
            args = case.get("args", [])
            try:
                if "raises" in case:
                    try:
                        fn(*args)
                    except Exception as exc:
                        if type(exc).__name__ != case["raises"]:
                            failures.append("hidden '%s' case %d: wrong exception %s"
                                            % (name, i, type(exc).__name__))
                    else:
                        failures.append("hidden '%s' case %d: expected %s, no raise"
                                        % (name, i, case["raises"]))
                else:
                    got = fn(*args)
                    if not eq(got, case.get("expect")):
                        failures.append("hidden '%s' case %d: %s%s -> %r, want %r"
                                        % (name, i, fname, args, got, case.get("expect")))
            except Exception as exc:
                failures.append("hidden '%s' case %d raised %s: %r"
                                % (name, i, type(exc).__name__, exc))

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
