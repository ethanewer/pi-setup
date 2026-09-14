#!/usr/bin/env python3
"""Hidden case: ValidationError-state findings.

Upstream's regression cases always give the matched state a "block"ed per-state
action when asserting True, and never exercise an error-state finding whose
per-state action is "monitor" or missing. This driver checks the error state
directly: per-state action decides alone, general action ignored.
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


CASES = [
    # per-state error = monitor while general action = block: must NOT block
    ("error-per-state-monitor+general-block",
     make(["block"], {"valid": "comment", "invalid": "monitor", "error": "monitor"},
          out.ValidationError()), False),
    # per-state map without an "error" key: missing key must mean "not block"
    ("error-key-missing+general-block",
     make(["block"], {"valid": "comment"}, out.ValidationError()), False),
    # per-state error = block while general action = monitor: must block
    ("error-per-state-block+general-monitor",
     make(["monitor"], {"valid": "comment", "invalid": "monitor", "error": "block"},
          out.ValidationError()), True),
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