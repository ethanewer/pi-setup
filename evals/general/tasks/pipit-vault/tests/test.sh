#!/bin/bash
# Verifier for pipit-vault: byte-checks the visible /app/passcode.txt and
# EXECUTES the deliverable tool (/app/recover.py) on every hidden vault in
# /tests/hidden. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import os
import subprocess
import sys

TOOL = "/app/recover.py"
VISIBLE_VAULT = "/app/vault"
VISIBLE_OUT = "/app/passcode.txt"
VISIBLE_REF = "/tests/visible_reference.txt"

failures = []


def strict_match(raw, expected):
    """Exact normalization: contents must be expected, or expected + one \\n.
    Any other surrounding/trailing whitespace fails."""
    return raw == expected or raw == expected + "\n"


def run_tool(vault_dir, out_path):
    if os.path.exists(out_path):
        os.remove(out_path)
    try:
        return subprocess.run([sys.executable, TOOL, vault_dir, out_path],
                              capture_output=True, text=True, timeout=120)
    except Exception as exc:
        print("tool execution failed: %s" % exc, file=sys.stderr)
        return None


def check_output(out_path, expected):
    if not os.path.isfile(out_path):
        return "output file %s missing" % out_path
    try:
        with open(out_path) as fh:
            raw = fh.read()
    except Exception as exc:
        return "output file %s unreadable: %s" % (out_path, exc)
    if not strict_match(raw, expected):
        return ("contents %r do not match expected %r with exact normalization"
                % (raw, expected))
    return None


if not os.path.isfile(TOOL):
    failures.append("missing /app/recover.py")
else:
    # ---- visible deliverable ----
    try:
        with open(VISIBLE_REF) as fh:
            visible_expected = fh.read().strip()
    except Exception as exc:
        visible_expected = None
        failures.append("visible reference unreadable: %s" % exc)
    if visible_expected is not None:
        if not os.path.isdir(VISIBLE_VAULT):
            failures.append("visible vault %s missing" % VISIBLE_VAULT)
        else:
            problems = check_output(VISIBLE_OUT, visible_expected)
            if problems:
                failures.append(problems)

    # ---- hidden cases ----
    hidden_dir = "/tests/hidden"
    cases = sorted(os.listdir(hidden_dir)) if os.path.isdir(hidden_dir) else []
    if not cases:
        failures.append("no hidden cases present")
    for case in cases:
        base = os.path.join(hidden_dir, case)
        vault = os.path.join(base, "vault")
        out_path = "/tmp/pv_passcode_%s.txt" % case
        if case == "corrupt":
            # tampered checksum: tool must fail cleanly and write nothing
            r = run_tool(vault, out_path)
            if r is None:
                failures.append("hidden '%s': tool crashed instead of failing cleanly" % case)
            elif r.returncode == 0:
                failures.append("hidden '%s': tool exited 0 despite checksum mismatch" % case)
            elif os.path.exists(out_path):
                failures.append("hidden '%s': output written despite checksum mismatch" % case)
            continue
        ref_path = os.path.join(base, "reference.txt")
        if not (os.path.isdir(vault) and os.path.isfile(ref_path)):
            failures.append("hidden '%s' malformed" % case)
            continue
        try:
            with open(ref_path) as fh:
                expected = fh.read().strip()
        except Exception as exc:
            failures.append("hidden '%s': reference unreadable: %s" % (case, exc))
            continue
        r = run_tool(vault, out_path)
        if r is None:
            failures.append("hidden '%s': tool could not run" % case)
            continue
        if r.returncode != 0:
            failures.append("hidden '%s': tool exited %d (%s)"
                            % (case, r.returncode, r.stderr[-200:]))
            continue
        problems = check_output(out_path, expected)
        if problems:
            failures.append("hidden '%s': %s" % (case, problems))

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
