#!/usr/bin/env python3
"""Apply the fix for the case-insensitive label-matcher prefix bug.

The label matchers' public Prefix() API advertises a byte-for-byte prefix that
is only guaranteed when the regex's leading literal is matched
case-sensitively. When the matcher is case-insensitive (inline (?i) flag), the
optimizer stored the case-folded literal (e.g. "ABC") and Prefix() returned it,
so consumers pre-filtering label names by byte comparison dropped names whose
capitalization differs from what the regex actually matches. The fix: never
advertise the prefix when the leading literal is case-insensitive.

Usage: fix_matcher.py <path-to-matcher.go>
"""
import sys


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else "model/labels/matcher.go"
    with open(path, encoding="utf-8") as f:
        src = f.read()

    old = '''// Prefix returns the required prefix of the value to match, if possible.
// It will be empty if it's an equality matcher or if the prefix can't be determined.
func (m *Matcher) Prefix() string {
	if m.re == nil {
		return ""
	}
	return m.re.prefix
}'''

    new = '''// Prefix returns the required prefix of the value to match byte-for-byte, if possible.
// It will be empty if it's an equality matcher or if the prefix can't be determined.
func (m *Matcher) Prefix() string {
	if m.re == nil || m.re.caseInsensitivePrefix {
		return ""
	}
	return m.re.prefix
}'''

    if old not in src:
        print(f"ERROR: expected parent matcher.go block not found in {path}", file=sys.stderr)
        return 1

    with open(path, "w", encoding="utf-8") as f:
        f.write(src.replace(old, new))
    print(f"patched {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())