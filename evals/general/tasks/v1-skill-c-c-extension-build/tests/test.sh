#!/usr/bin/env bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier

ext_ok=0
if python3 - <<'PY_END'
import json, sys
sys.path.insert(0, "/app/native")
try:
    import quickcalc
    assert quickcalc.add(7, 3) == 10
    assert quickcalc.sub(7, 3) == 4
    d = json.load(open("/app/native/build_report.json"))
    assert d.get("extension") == "quickcalc"
    assert d.get("cli_worked") is True
except Exception:
    sys.exit(1)
sys.exit(0)
PY_END
then
  ext_ok=1
fi

cli_ok=0
if [ -x /app/native/calc_cli ]; then
  if [ "$(/app/native/calc_cli 7 3)" = "add=10 sub=4" ]; then
    cli_ok=1
  fi
fi

reward=0
if [ "$ext_ok" = 1 ] && [ "$cli_ok" = 1 ]; then
  reward=1
elif [ "$ext_ok" = 1 ] || [ "$cli_ok" = 1 ]; then
  reward=0
fi
echo "$reward" > /logs/verifier/reward.txt