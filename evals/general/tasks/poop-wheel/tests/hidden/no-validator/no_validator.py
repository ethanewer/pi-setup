#!/usr/bin/env python3
"""Hidden case: NoValidator (no validator ran) findings.

Upstream's regression cases exercise NoValidator with either all states
blocked or a full map plus a general action. This driver covers a
no-validator finding whose per-state map blocks only "valid" (the state the
buggy code wrongly fell back to) and an empty per-state map.
"""
import sys

import semgrep.semgrep_interfaces.semgrep_output_v1 as out
from semgrep.rule_match import RuleMatch


def make(general_actions, per_state):
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
                validation_state=out.ValidationState(out.NoValidator()),
            ),
        ),
    )


CASES = [
    # no validator + per-state blocks only "valid" + general monitor: must NOT
    # block (per-state map must be ignored for no-validator findings)
    ("novalidator+per-state-only-valid-block+general-monitor",
     make(["monitor"], {"valid": "block"}), False),
    # no validator + per-state all block + general monitor: must NOT block
    ("novalidator+per-state-all-block+general-monitor",
     make(["monitor"], {"valid": "block", "invalid": "block", "error": "block"}), False),
    # no validator + empty per-state map + general block: must block
    ("novalidator+empty-per-state+general-block",
     make(["block"], {}), True),
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