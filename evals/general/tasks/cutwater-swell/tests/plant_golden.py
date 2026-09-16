#!/usr/bin/env python3
"""Plant the upstream regression test into the tests module of the agent's
fixed crates/regex/src/literal.rs and require it to fail there.

The golden function is the sha256-pinned bytes extracted from the fix commit
at image build time (/opt/golden/case_insensitive_alternation.rs). It is
inserted inside the `#[cfg(test)] mod tests` block (immediately before the
file's final closing brace), replacing any same-named function the agent may
have written (typically a no-op copy or a weakened assertion). The verifier
runs the project's own cargo test on the result, so a real fix is required.
"""
import re
import sys

LIT = "/app/src/crates/regex/src/literal.rs"
GOLDEN = "/opt/golden/case_insensitive_alternation.rs"


def main() -> int:
    try:
        text = open(LIT, encoding="utf-8").read().rstrip("\n")
    except OSError as e:
        print(f"plant_golden: cannot read {LIT}: {e}", file=sys.stderr)
        return 1
    if not text.endswith("}"):
        print("plant_golden: literal.rs does not end with the tests-module close",
              file=sys.stderr)
        return 1
    try:
        gold = open(GOLDEN, encoding="utf-8").read().rstrip("\n")
    except OSError as e:
        print(f"plant_golden: cannot read {GOLDEN}: {e}", file=sys.stderr)
        return 1
    if "fn case_insensitive_alternation" not in gold:
        print("plant_golden: golden bytes do not contain the regression test",
              file=sys.stderr)
        return 1
    # Strip any pre-existing same-named test (attribute + fn through its
    # closing brace), so a planted/weakened/duplicated copy cannot survive.
    pat = re.compile(
        r"\n    #\[test\]\n    fn case_insensitive_alternation\(\) \{.*?\n    \}\n",
        re.S,
    )
    text, n = pat.subn("\n", text)
    if n:
        print(f"plant_golden: stripped {n} pre-existing copy of the test", file=sys.stderr)
    text = text.rstrip("\n")
    assert text.endswith("}")
    text = text[:-1] + "\n" + gold + "\n}\n"
    try:
        open(LIT, "w", encoding="utf-8").write(text)
    except OSError as e:
        print(f"plant_golden: cannot write {LIT}: {e}", file=sys.stderr)
        return 1
    print("plant_golden: golden regression test planted inside mod tests")
    return 0


if __name__ == "__main__":
    sys.exit(main())