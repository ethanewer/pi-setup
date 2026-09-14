#!/usr/bin/env python3
"""Apply the minimal fix for the validator-rule blocking bug to rule_match.py.

The bug: for findings that went through validation, is_blocking() OR-ed the
rule's general dev.semgrep.actions flag into the per-validation-state
decision, so a rule whose general action was "block" blocked *every*
validation state even when the per-state action for that state said
"monitor" (or "comment"). Additionally, is_validation_state_blocking()
mapped the NoValidator state to the "valid" per-state action instead of
falling back to the general rule action, so a validator-less finding could
be blocked by the per-state map alone.

The fix (the upstream semgrep/semgrep resolution of issue #9943):
  * NoValidator findings fall back to the general dev.semgrep.actions flag;
  * all other validation states consult ONLY dev.semgrep.validation_state.actions;
  * is_blocking() returns the per-state decision alone when a validation
    state exists, and the general rule action otherwise.
"""
import sys


def apply(path: str) -> str:
    with open(path, "r", encoding="utf-8") as f:
        src = f.read()

    # 1. NoValidator special case + per-state-only map in is_validation_state_blocking
    old_map = (
        "        action_map = {\n"
        "            out.ConfirmedValid: \"valid\",\n"
        "            out.ConfirmedInvalid: \"invalid\",\n"
        "            out.ValidationError: \"error\",\n"
        "            out.NoValidator: \"valid\",  # Fallback to valid action for no validator\n"
        "        }\n"
        "\n"
        "        validation_state = action_map.get(type(self.validation_state.value))\n"
    )
    new_map = (
        "        validation_state_type = type(self.validation_state.value)\n"
        "        if validation_state_type is out.NoValidator:\n"
        "            # If there is no validator, we should rely on original dev.semgrep.actions\n"
        "            return \"block\" in self.metadata.get(\"dev.semgrep.actions\", [\"block\"])\n"
        "\n"
        "        action_map = {\n"
        "            out.ConfirmedValid: \"valid\",\n"
        "            out.ConfirmedInvalid: \"invalid\",\n"
        "            out.ValidationError: \"error\",\n"
        "            # NOTE(sal): this exists purely for the sake of the type checker\n"
        "            out.NoValidator: \"valid\",\n"
        "        }\n"
        "\n"
        "        validation_state: str = action_map.get(validation_state_type, \"valid\")\n"
    )
    assert src.count(old_map) == 1, "is_validation_state_blocking block not found exactly once"
    src = src.replace(old_map, new_map)

    # 2. is_blocking(): the validation-state branch returns the per-state decision alone
    old_tail = (
        "        else:\n"
        "            return self.is_validation_state_blocking or blocking\n"
    )
    new_tail = (
        "        elif self.validation_state is not None:\n"
        "            return self.is_validation_state_blocking\n"
        "\n"
        "        return blocking\n"
    )
    assert src.count(old_tail) == 1, "is_blocking tail not found exactly once"
    src = src.replace(old_tail, new_tail)

    with open(path, "w", encoding="utf-8") as f:
        f.write(src)
    return src


if __name__ == "__main__":
    apply(sys.argv[1])
    print("patched", sys.argv[1])