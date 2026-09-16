#!/usr/bin/env python3
"""Apply the relabel config round-trip fix to prometheus' model/relabel/relabel.go.

Two changes, from the bug's root cause:
  1. The Config struct marks Separator and Replacement `omitempty` in their
     yaml/json marshal attributes.  UnmarshalYAML seeds the struct from
     DefaultRelabelConfig (a ";" separator, a "$1" replacement, both
     non-empty), so an empty Separator/Replacement in memory can only mean the
     user explicitly configured it -- it must be serialized, not dropped, and
     it must not fall back to the defaults after a reload.
  2. Regexp.MarshalYAML drops any regex whose *source string* is empty.  A
     deliberately empty regex ("") is a real configuration that must round-trip
     as "", so the marshaller must omit only a regex that was never set
     (nil compiled regexp), not one whose string is empty.

Idempotent; exits non-zero if the expected snippets are not all present and
applied.
"""

import sys
from pathlib import Path

REPLACEMENTS = [
    (
        'Separator string `yaml:"separator,omitempty" json:"separator,omitempty"`',
        'Separator string `yaml:"separator" json:"separator"`',
    ),
    (
        'Replacement string `yaml:"replacement,omitempty" json:"replacement,omitempty"`',
        'Replacement string `yaml:"replacement" json:"replacement"`',
    ),
    (
        '''// MarshalYAML implements the yaml.Marshaler interface.
func (re Regexp) MarshalYAML() (any, error) {
	if re.String() != "" {
		return re.String(), nil
	}
	return nil, nil
}''',
        '''// MarshalYAML implements the yaml.Marshaler interface.
func (re Regexp) MarshalYAML() (any, error) {
	if re.Regexp == nil {
		return nil, nil
	}
	return re.String(), nil
}''',
    ),
]


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_relabel.py PATH", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    src = path.read_text(encoding="utf-8")

    if ('yaml:"separator" json:"separator"' in src
            and 'yaml:"replacement" json:"replacement"' in src
            and "re.Regexp == nil" in src):
        print("relabel.go already carries the round-trip fix")
        return 0

    applied = 0
    for old, new in REPLACEMENTS:
        if old in src:
            src = src.replace(old, new, 1)
            applied += 1
        elif new in src:
            applied += 1  # already applied by a previous run
        else:
            print("FATAL: expected snippet not found in source:", file=sys.stderr)
            print(old, file=sys.stderr)
            return 1

    if applied != len(REPLACEMENTS):
        print(f"FATAL: expected {len(REPLACEMENTS)} edits, applied {applied}", file=sys.stderr)
        return 1

    path.write_text(src, encoding="utf-8")
    print(f"ok: explicit empty separator/replacement now round-trip in {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())