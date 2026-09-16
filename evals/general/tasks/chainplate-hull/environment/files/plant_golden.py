#!/usr/bin/env python3
"""Plant the golden unit-test module into a formatter source file.

Replaces the inline `#[cfg(test)] mod tests { .. }` block in
src/formatter/string_formatter.rs with the block read from the golden file
extracted from the upstream fix commit at image build time. The block is the
top-level `mod tests {` .. final `}` region that closes the file.

Usage:
    plant_golden.py <source.rs> <golden-tests.rs>

Exits non-zero (with a message) if the tests module cannot be found and
replaced, so callers can fail closed: a tree whose formatter file lost its
inline tests module cannot be graded on the project's own tests.
"""
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: plant_golden.py <source.rs> <golden-tests.rs>", file=sys.stderr)
        return 2
    src_path, golden_path = sys.argv[1], sys.argv[2]

    lines = open(src_path).read().splitlines()
    try:
        start = next(i for i, l in enumerate(lines) if l.strip() == "mod tests {")
    except StopIteration:
        print(f"no 'mod tests {{' block found in {src_path}", file=sys.stderr)
        return 1
    end = len(lines) - 1
    if lines[end].strip() != "}":
        print(f"tests module does not close {src_path}", file=sys.stderr)
        return 1

    golden = open(golden_path).read()
    for name in ("test_empty_textgroup_with_style",
                 "test_empty_textgroup_without_style",
                 "test_empty_textgroup_propagates_prev_bg"):
        if name not in golden:
            print(f"golden block missing {name}", file=sys.stderr)
            return 1

    new_lines = lines[:start] + golden.splitlines() + lines[end + 1:]
    with open(src_path, "w") as fh:
        fh.write("\n".join(new_lines) + "\n")
    print(f"planted {golden.count(chr(10)) + 1} golden test lines into {src_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())