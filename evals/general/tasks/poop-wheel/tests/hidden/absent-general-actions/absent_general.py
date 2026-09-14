#!/usr/bin/env python3
"""Hidden case: metadata without the general dev.semgrep.actions key.

Upstream's regression cases always pass an explicit general action. Real
rules can omit the key, in which case the general action defaults to
["block"]. A finding WITH a validation state must ignore even that default:
the per-state map decides. A no-validator finding with the default general
action must block.
"""
import sys

import semgrep.semgrep_interfaces.semgrep_output_v1 as out
from semgrep.rule_match import RuleMatch


def make(per_state, state):
    # deliberately NO "dev.semgrep.actions" key: general action defaults to
    # ["block"]
    md = {"dev.semgrep.validation_state.actions": per_state}
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
    # no general key (defaults to block) + invalid per-state monitor: must NOT block
    ("no-general-key+invalid-per-state-monitor",
     make({"invalid": "monitor"}, out.ConfirmedInvalid()), False),
    # no general key + valid per-state comment: must NOT block
    ("no-general-key+valid-per-state-comment",
     make({"valid": "comment"}, out.ConfirmedValid()), False),
    # no general key + valid per-state block: must block
    ("no-general-key+valid-per-state-block",
     make({"valid": "block"}, out.ConfirmedValid()), True),
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