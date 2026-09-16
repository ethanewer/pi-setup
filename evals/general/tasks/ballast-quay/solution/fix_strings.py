#!/usr/bin/env python3
"""Apply the upstream fix for the mixed raw/non-raw implicit-str-concat
false positive to a pylint checkout.

The bug: StringConstantChecker processes string tokens and records only
``(str_eval(token), next_token)`` in ``self.string_tokens``, so the implicit
string concatenation check can never tell whether a literal is raw. As a
result W1404 is emitted for an implicit concatenation of a raw literal with a
non-raw one, even though such literals cannot be merged into a single string
and the juxtaposition is therefore deliberate.

The fix records the raw token text alongside the evaluated value and, in the
check, skips the pair when the two adjacent literals differ in rawness.

Usage: fix_strings.py [path-to-strings.py]
"""
import pathlib
import sys

DEFAULT = "/app/src/pylint/checkers/strings.py"

HUNKS = [
    # 1. widen the recorded token tuple to carry the raw token text
    (
        """        self.string_tokens: dict[
            tuple[int, int], tuple[str, tokenize.TokenInfo | None]
        ] = {}
        \"\"\"Token position -> (token value, next token).\"\"\"
""",
        """        self.string_tokens: dict[
            tuple[int, int], tuple[str, str, tokenize.TokenInfo | None]
        ] = {}
        \"\"\"Token position -> (token value, raw token text, next token).\"\"\"
""",
    ),
    # 2. store the raw token text next to the evaluated value
    (
        """                    self.string_tokens[start] = (str_eval(token), next_token)
""",
        """                    self.string_tokens[start] = (str_eval(token), token, next_token)
""",
    ),
    # 3. unpack the widened tuple at the one call site
    (
        """            matching_token, next_token = self.string_tokens[token_index]
""",
        """            matching_token, token_string, next_token = self.string_tokens[token_index]
""",
    ),
    # 4. skip a pair whose literals differ in rawness: they cannot be merged
    #    into a single literal, so the concatenation is deliberate
    (
        """                and next_token.type == tokenize.STRING
            ):
                if next_token.start[0] == elt.lineno or (
""",
        """                and next_token.type == tokenize.STRING
            ):
                # A raw string concatenated with a non-raw one (or vice versa)
                # cannot be merged into a single literal, so the concatenation
                # is deliberate rather than a forgotten comma.
                if _is_raw_string_token(token_string) != _is_raw_string_token(
                    next_token.string
                ):
                    continue
                if next_token.start[0] == elt.lineno or (
""",
    ),
    # 5. add the rawness predicate next to the other token helpers
    (
        """def _is_long_string(string_token: str) -> bool:
    \"\"\"Is this string token a "longstring" (is it triple-quoted)?
""",
        """def _is_raw_string_token(token: str) -> bool:
    \"\"\"Return whether a string token is a raw string (has an ``r``/``R`` prefix).

    Only the prefix markers that precede the opening quote are inspected, e.g.
    ``r"foo"`` and ``Rb"foo"`` are raw while ``"foo"`` and ``f"foo"`` are not.
    \"\"\"
    for char in token:
        if char in "'\\\"":
            break
        if char in "rR":
            return True
    return False


def _is_long_string(string_token: str) -> bool:
    \"\"\"Is this string token a "longstring" (is it triple-quoted)?
""",
    ),
]


def main() -> int:
    path = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else DEFAULT)
    src = path.read_text()
    for i, (old, new) in enumerate(HUNKS):
        if new in src:
            continue  # this hunk already applied
        if src.count(old) != 1:
            print(
                f"error: hunk {i} not found exactly once in {path}",
                file=sys.stderr,
            )
            return 1
        src = src.replace(old, new)
    path.write_text(src)
    print(f"fixed {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())