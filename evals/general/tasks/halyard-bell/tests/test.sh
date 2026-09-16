#!/bin/bash
# Verifier for halyard-bell (executes-deliverable).
#
# The agent writes Prometheus alerting rules at /app/alerting/alerts.yml.
# This verifier proves the rules are syntactically valid with `promtool check
# rules`, then proves the fire-on-right / don't-fire-on-the-wrong behaviour
# with `promtool test rules` against the shipped visible scenario and the four
# hidden scenario files under /tests/hidden (which include healthy-but-busy
# input series that an over-broad rule must NOT page on).
#
# Writes /logs/verifier/reward.txt (1 = all pass, 0 = any fail).
# Guarantee a reward on every exit path.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier

RULES="/app/alerting/alerts.yml"

if [ ! -f "$RULES" ]; then
  echo "missing deliverable $RULES" >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

python3 - <<'PY'
import os
import subprocess
import sys

RULES = "/app/alerting/alerts.yml"
failures = []


def fail(msg):
    print("FAIL: " + msg)
    failures.append(msg)


def run(argv):
    return subprocess.run(argv, capture_output=True, text=True)


# 1) syntactic validity of the rules file
r = run(["promtool", "check", "rules", RULES])
if r.returncode != 0:
    fail("promtool check rules failed: %s" % r.stdout.strip())

# 2) the shipped visible scenario must be green against the delivered rules
visible = "/app/yard/monitoring/tests/visible_scenario.yml"
if not os.path.exists(visible):
    fail("visible scenario missing: %s" % visible)
else:
    r = run(["promtool", "test", "rules", visible])
    if r.returncode != 0:
        tail = "\n".join(r.stdout.strip().splitlines()[-30:])
        fail("visible scenario failed: %s" % tail)

# 3) every hidden scenario must be green (>= 2 cases, genuinely hidden)
hidden_dir = "/tests/hidden"
hidden_cases = sorted(
    n for n in os.listdir(hidden_dir)
    if os.path.isdir(os.path.join(hidden_dir, n))
)
if len(hidden_cases) < 2:
    fail("expected >=2 hidden cases, found %d" % len(hidden_cases))
for case in hidden_cases:
    scenario = os.path.join(hidden_dir, case, "scenario.yml")
    if not os.path.exists(scenario):
        fail("%s: no scenario.yml" % case)
        continue
    r = run(["promtool", "test", "rules", scenario])
    if r.returncode != 0:
        tail = "\n".join(r.stdout.strip().splitlines()[-25:])
        fail("%s: hidden scenario failed: %s" % (case, tail))

if failures:
    print("RULES DID NOT PASS ALL SCENARIOS (%d failure(s))." % len(failures))
    open("/logs/verifier/reward.txt", "w").write("0")
    sys.exit(0)

print("ALL PASS: check rules OK; visible + all %d hidden scenarios green."
      % len(hidden_cases))
open("/logs/verifier/reward.txt", "w").write("1")
sys.exit(0)
PY
