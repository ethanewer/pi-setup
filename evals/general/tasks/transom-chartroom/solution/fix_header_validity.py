#!/usr/bin/env python3
"""Apply the upstream fix for the trailing-newline header-validity bug.

The header name/value validity checks in src/requests/_internal_utils.py
anchor their patterns with '$', which in Python's re module matches just
before a trailing newline, so a header name or value ending in '\\n' slips
through validation. Every occurrence is re-anchored to '\\Z', the true
end-of-string anchor, which rejects trailing newlines like any other return
character.

This mirrors upstream commit bc7dd0fc4d56e808bcdd85ac2d797b3107c89259
("Fix cosmetic header validity parsing regex (#7308)") exactly.
"""
import sys

PATH = "src/requests/_internal_utils.py"

OLD = [
    '_VALID_HEADER_NAME_RE_BYTE = re.compile(rb"^[^:\\s][^:\\r\\n]*$")',
    '_VALID_HEADER_NAME_RE_STR = re.compile(r"^[^:\\s][^:\\r\\n]*$")',
    '_VALID_HEADER_VALUE_RE_BYTE = re.compile(rb"^\\S[^\\r\\n]*$|^$")',
    '_VALID_HEADER_VALUE_RE_STR = re.compile(r"^\\S[^\\r\\n]*$|^$")',
]
NEW = [
    '_VALID_HEADER_NAME_RE_BYTE = re.compile(rb"^[^:\\s][^:\\r\\n]*\\Z")',
    '_VALID_HEADER_NAME_RE_STR = re.compile(r"^[^:\\s][^:\\r\\n]*\\Z")',
    '_VALID_HEADER_VALUE_RE_BYTE = re.compile(rb"^\\S[^\\r\\n]*\\Z|^\\Z")',
    '_VALID_HEADER_VALUE_RE_STR = re.compile(r"^\\S[^\\r\\n]*\\Z|^\\Z")',
]


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} /path/to/requests-src-root", file=sys.stderr)
        return 2
    src = sys.argv[1].rstrip("/")
    path = f"{src}/{PATH}"
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    replaced = 0
    for old, new in zip(OLD, NEW):
        if old in text and text.count(old) == 1:
            text = text.replace(old, new)
            replaced += 1
    if replaced != len(OLD):
        print(
            f"error: expected {len(OLD)} exact lines to replace, replaced {replaced}; "
            "file does not match the pinned parent state",
            file=sys.stderr,
        )
        return 1
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    print(f"fixed {replaced} header-validity patterns in {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())