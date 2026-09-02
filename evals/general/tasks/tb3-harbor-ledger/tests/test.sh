#!/bin/bash
# tb3-harbor-ledger verifier. Executes the deliverable /app/adjudicate.py on
# the visible fixtures and (via /tests/hidden/adjudicate_probe.py) on hidden
# (policy, claims) bundles, comparing every output against an independent
# recomputation; also requires /app/adjudication.json to match the visible
# recomputation. Writes reward 0/1 to /logs/verifier/reward.txt on EVERY
# exit path (EXIT trap).
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

log() { echo "tb3-harbor-ledger verify: $*" >&2; }

# ---------------------------------------------------------------------------
# 1. Deliverables present as non-empty files.
# ---------------------------------------------------------------------------
for f in /app/adjudicate.py /app/adjudication.json; do
  if [ ! -s "$f" ]; then
    overall=0; msgs="$msgs missing:$f"
  fi
done

# ---------------------------------------------------------------------------
# 2. Baseline: execute the deliverable CLI on the visible fixtures.
# ---------------------------------------------------------------------------
if [ "$overall" = "1" ]; then
  rm -f /tmp/harbor_visible_out.json
  $TIMEOUT_CMD 60 python3 /app/adjudicate.py \
        /app/policy.json /app/claims.jsonl /tmp/harbor_visible_out.json \
        >/tmp/harbor_cli.log 2>&1
  rc=$?
  if [ "$rc" -ne 0 ]; then
    overall=0; msgs="$msgs visible-cli:exit:$rc"
  fi
fi

# ---------------------------------------------------------------------------
# 3. Full battery: visible recompute, report deliverable, hidden bundles.
# ---------------------------------------------------------------------------
if [ "$overall" = "1" ]; then
  if ! $TIMEOUT_CMD 120 python3 /tests/hidden/adjudicate_probe.py \
        >/tmp/harbor_probe.log 2>&1; then
    overall=0; msgs="$msgs probe:failed"
    tail -20 /tmp/harbor_probe.log >&2 2>/dev/null || true
  fi
fi

log "result:${msgs:-ok}"
exit 0