#!/bin/bash
#
# cedar-summit verifier. Brings the offsite stack up (idempotent), statically
# validates /app/offsite_plan.json, executes the deliverable against the
# coordinator's booking desk (hidden group state), then runs the hidden probe
# suites in /tests/hidden: exact plan optimality, call-journal evidence of the
# authenticated conversations, and the wrong-phrase hang-up regression.
# Writes REWARD (0/1) to /logs/verifier/reward.txt on EVERY exit path
# (EXIT trap).
set -u

mkdir -p /logs/verifier

TIMEOUT_CMD=$(command -v timeout || true)
[ -n "${TIMEOUT_CMD-}" ] || TIMEOUT_CMD=""

overall=1
msgs=""

finalize_reward() {
  if [ "${overall:-0}" = "1" ]; then
    printf 1 > /logs/verifier/reward.txt
  else
    printf 0 > /logs/verifier/reward.txt
  fi
}
trap 'finalize_reward' EXIT
printf 0 > /logs/verifier/reward.txt

log() { echo "cedar-summit verify: $*" >&2; }

# ---------------------------------------------------------------------------
# 1. The four microservices must be serving (idempotent bring-up).
# ---------------------------------------------------------------------------
if ! $TIMEOUT_CMD 90 bash /opt/offsite/up.sh >/tmp/cs_up.log 2>&1; then
  overall=0; msgs="$msgs stack:up-failed"
  tail -5 /tmp/cs_up.log >&2 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 2. Static check of the deliverable.
# ---------------------------------------------------------------------------
if [ "$overall" = "1" ]; then
  if [ ! -f /app/offsite_plan.json ]; then
    overall=0; msgs="$msgs missing:offsite_plan.json"
  else
    if ! $TIMEOUT_CMD 30 python3 - <<'PY'
import json, re, sys
try:
    plan = json.load(open("/app/offsite_plan.json"))
except Exception as exc:
    print("plan does not parse as JSON: %s" % exc, file=sys.stderr)
    sys.exit(1)
if not isinstance(plan, dict) or set(plan) != {"date", "activity",
                                                "venue", "start_time"}:
    print("plan keys must be exactly date/activity/venue/start_time",
          file=sys.stderr)
    sys.exit(1)
if not all(isinstance(v, str) for v in plan.values()):
    print("plan values must be strings", file=sys.stderr)
    sys.exit(1)
if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", plan["date"]):
    print("bad date format", file=sys.stderr); sys.exit(1)
if not re.fullmatch(r"\d{2}:\d{2}", plan["start_time"]):
    print("bad start_time format", file=sys.stderr); sys.exit(1)
PY
    then
      overall=0; msgs="$msgs plan:spec-mismatch"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 3. Execute the deliverable: submit it to the booking desk, which validates
#    it against the group's hidden state (feasibility gate).
# ---------------------------------------------------------------------------
if [ "$overall" = "1" ]; then
  if ! $TIMEOUT_CMD 30 python3 - <<'PY'
import json, sys, urllib.request
plan = json.load(open("/app/offsite_plan.json"))
req = urllib.request.Request(
    "http://127.0.0.1:8701/book",
    data=json.dumps(plan).encode(),
    headers={"Content-Type": "application/json",
             "X-Offsite-Admin": "offsite-admin-9f3c"},
    method="POST")
with urllib.request.urlopen(req, timeout=10) as r:
    body = json.load(r)
if body.get("status") != "booked":
    print("booking desk rejected the plan: %s" % body, file=sys.stderr)
    sys.exit(1)
PY
  then
    overall=0; msgs="$msgs booking:rejected"
  fi
fi

# ---------------------------------------------------------------------------
# 4. Hidden probes (run in order; each is self-contained).
# ---------------------------------------------------------------------------
if [ "$overall" = "1" ]; then
  probes=0
  for p in /tests/hidden/probe_*/probe.py; do
    [ -f "$p" ] || continue
    probes=$((probes+1))
    if ! $TIMEOUT_CMD 60 python3 "$p" >/tmp/cs_probe.log 2>&1; then
      overall=0
      msgs="$msgs probe-failed:$(basename "$(dirname "$p")")"
      tail -5 /tmp/cs_probe.log >&2 2>/dev/null || true
    fi
  done
  [ "$probes" -ge 1 ] || { overall=0; msgs="$msgs no-hidden-probes"; }
fi

if [ "$overall" = "1" ]; then
  log "all checks passed"
else
  log "FAIL${msgs:+:${msgs}}"
fi
finalize_reward
exit 0
