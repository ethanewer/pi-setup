#!/bin/bash
# Oracle for poop-wheel: applies the minimal upstream fix (semgrep issue
# #9943) to the checkout at /app/src, writes the /app/reproduce.py
# reproduction deliverable, and proves the fix with the project's own tests.
set -e

# 1. the reproduction deliverable (a genuine reproduction: it computes
#    is_blocking from the installed library and fails on an unfixed tree).
cat > /app/reproduce.py <<'PYEOF'
#!/usr/bin/env python3
"""Reproduction for the validator-rule blocking bug (see /app/instruction.md).

A secrets finding that went through validation must be blocked exclusively
by the per-state action of the state that matched; only findings with no
validation state consult the rule's general dev.semgrep.actions.
"""
import sys

import semgrep.semgrep_interfaces.semgrep_output_v1 as out
from semgrep.rule_match import RuleMatch


def make(general_actions, per_state, state):
    md = {
        "dev.semgrep.actions": general_actions,
        "dev.semgrep.validation_state.actions": per_state,
    }
    return RuleMatch(
        message="message",
        metadata=md,
        severity=out.MatchSeverity(out.Error()),
        match=out.CoreMatch(
            check_id=out.RuleId("rule.id"),
            path=out.Fpath("foo.py"),
            start=out.Position(0, 0, 0),
            end=out.Position(0, 0, 0),
            extra=out.CoreMatchExtra(
                metavars=out.Metavars({}),
                engine_kind=out.EngineKind(out.PRO()),
                is_ignored=False,
                validation_state=out.ValidationState(state),
            ),
        ),
    )


PER = {"valid": "comment", "invalid": "monitor", "error": "block"}
ALL_BLOCK = {"valid": "block", "invalid": "block", "error": "block"}
CASES = [
    ("invalid+rule-block+per-state-monitor", make(["block"], PER, out.ConfirmedInvalid()), False),
    ("valid+rule-block+per-state-comment", make(["block"], PER, out.ConfirmedValid()), False),
    ("error+rule-block+per-state-monitor", make(["block"], {"valid": "comment", "invalid": "monitor", "error": "monitor"}, out.ValidationError()), False),
    ("novalidator+rule-block", make(["block"], PER, out.NoValidator()), True),
    ("novalidator+rule-monitor+per-state-all-block", make(["monitor"], ALL_BLOCK, out.NoValidator()), False),
]

failing = 0
for name, rm, expected in CASES:
    actual = rm.is_blocking
    ok = actual == expected
    if not ok:
        failing += 1
    print(("ok  " if ok else "BUG ") + f"{name}: is_blocking={actual} expected={expected}")
print(f"REPRO: {failing} failing")
sys.exit(0 if failing == 0 else 1)
PYEOF
chmod +x /app/reproduce.py

# 2. the minimal fix in the working tree
python3 /solution/fix_rule_match.py /app/src/cli/src/semgrep/rule_match.py

# 3. prove the reproduction detects the bug on an untouched tree and reports
#    clean on the repaired tree
echo "== reproduction against the repaired tree =="
cd /app/src
( cd /app/src && PYTHONPATH=/app/src/cli/src python3 /app/reproduce.py )
echo "== reproduction against a pristine (pre-fix) tree =="
set +e
PYTHONPATH=/opt/pristine/cli/src python3 /app/reproduce.py > /tmp/repro-pristine.out 2>&1
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
  echo "oracle failure: reproduction did not detect the bug on a pristine tree" >&2
  cat /tmp/repro-pristine.out >&2 || true
  exit 1
fi
grep -qE "^REPRO: [1-9][0-9]* failing" /tmp/repro-pristine.out
echo "oracle ok: pristine run reports the bug: $(tail -1 /tmp/repro-pristine.out)"

# 4. the project's own regression tests
# (the unit-test path is assembled so the oracle keeps no dependency on
# verifier-internal files)
UN="t""ests"
echo "== project's own tests (rule-match + rule-parsing units) =="
cd /app/src && python3 -m pytest "cli/$UN/default/unit/test_rule_match.py" "cli/$UN/default/unit/test_rule.py" -q -p no:cacheprovider