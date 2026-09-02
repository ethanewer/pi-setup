#!/bin/bash
# Verifier for opal-notch: checks the visible deliverables are present and
# correct, ENFORCES the no-modify rule on /app/shell_policy.json, and EXECUTES
# the deliverable script (/app/setup.sh) on the visible policy and on every
# hidden policy in /tests/hidden, then queries the live account database
# (getent passwd) to confirm each login shell was actually changed.
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible policy in /app (the instruction tells
# the agent not to modify it; tampering defeats the visible-case check).
PRISTINE_POLICY_SHA="a57b096220a7468a6454b49449f5e664740e1dafd2a782be9969d0d9b8e859ff"

policy_ok=1
if [ ! -f /app/shell_policy.json ]; then
    echo "no-modify: /app/shell_policy.json missing" >&2
    policy_ok=0
else
    actual="$(sha256sum /app/shell_policy.json | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_POLICY_SHA" ]; then
        echo "no-modify: /app/shell_policy.json was modified" >&2
        policy_ok=0
    fi
fi

python3 - "$policy_ok" <<'PY'
import json
import os
import shutil
import subprocess
import sys

SETUP = "/app/setup.sh"
REPORT = "/app/shell_report.json"
POLICY = "/app/shell_policy.json"
no_modify_broken = int(sys.argv[1])

failures = []
if no_modify_broken == 1:
    pass
else:
    failures.append("visible policy modified or missing (no-modify rule)")


def account_shell(user):
    """Live user-database lookup of the login shell (last passwd field)."""
    r = subprocess.run(["getent", "passwd", user],
                       capture_output=True, text=True, timeout=30)
    if r.returncode != 0 or not r.stdout.strip():
        return None
    return r.stdout.rstrip("\n").split(":")[-1]


def load_json(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def apply_case(policy_src, expected_path, label):
    """Copy the policy into place, EXECUTE the deliverable, then check the
    live account database and the report against the case expectation."""
    case_fail = []
    try:
        expected = load_json(expected_path)
        assert isinstance(expected, dict) and expected, "bad expected"
        if os.path.abspath(policy_src) != os.path.abspath(POLICY):
            shutil.copyfile(policy_src, POLICY)
    except Exception as exc:
        return ["%s: bad case fixtures (%s)" % (label, exc)]

    r = subprocess.run(["bash", SETUP], capture_output=True, text=True,
                       timeout=120)
    if r.returncode != 0:
        case_fail.append("%s: setup.sh exited %d" % (label, r.returncode))

    # The authoritative check: the account database itself.
    actual = {}
    for user in sorted(expected):
        actual[user] = account_shell(user)
        if actual[user] != expected[user]:
            case_fail.append("%s: account %s shell is %r, want %r"
                             % (label, user, actual[user], expected[user]))

    # The report deliverable must reflect the live account database for the
    # policy's accounts.
    try:
        report = load_json(REPORT)
        assert isinstance(report, dict), "report is not an object"
    except Exception as exc:
        report = None
        case_fail.append("%s: shell_report.json unreadable (%s)"
                         % (label, exc))
    if report is not None:
        try:
            policy = load_json(POLICY)
            want = {u: actual.get(u) for u in policy.get("accounts", {})}
            if report != want:
                case_fail.append("%s: shell_report.json mismatch (%r != %r)"
                                 % (label, report, want))
        except Exception as exc:
            case_fail.append("%s: policy unreadable (%s)" % (label, exc))
    return case_fail


if not os.path.isfile(SETUP):
    failures.append("missing /app/setup.sh")
else:
    # --- visible case: policy in /app, expected in /tests/expected.json ---
    if os.path.isfile(POLICY) and os.path.isfile("/tests/expected.json"):
        failures.extend(apply_case(POLICY, "/tests/expected.json", "visible"))
    else:
        failures.append("visible inputs missing")

    # --- hidden cases: distinct policies with their own expectations ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            pol = os.path.join(base, "policy.json")
            exp = os.path.join(base, "expected.json")
            if not (os.path.isfile(pol) and os.path.isfile(exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            failures.extend(apply_case(pol, exp, c))
    else:
        failures.append("no hidden cases directory")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0