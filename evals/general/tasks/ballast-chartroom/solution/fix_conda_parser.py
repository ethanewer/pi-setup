#!/usr/bin/env python3
"""Fix trivy's conda environment-file parser panic on operator-only lines.

`parseDependency()` normalises a dependency line by replacing version
operators (">", "<", "=") with spaces and then splitting it into fields, and
then indexes the first field. A dependency entry that consists *only* of such
characters (a bare "=", "==", or any run/spacing of them) leaves nothing
behind once the operators are replaced, so the split is empty and the index
[0] access panics with "index out of range [0] with length 0", aborting the
whole scan.

The fix returns an empty name/version pair as soon as the split produced no
fields. Callers already skip packages whose name is empty, so the meaningless
entry is dropped and scanning continues with the rest of the file.

Usage: fix_conda_parser.py [path-to-parse.go]
"""
import pathlib
import sys

DEFAULT = "/app/src/pkg/dependency/parser/conda/environment/parse.go"

OLD = (
    "\tparts := strings.Fields(line)\n"
    "\tname := parts[0]\n"
)

NEW = (
    "\tparts := strings.Fields(line)\n"
    "\tif len(parts) == 0 {\n"
    "\t\treturn \"\", \"\"\n"
    "\t}\n"
    "\tname := parts[0]\n"
)


def main() -> int:
    target = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else DEFAULT)
    text = target.read_text()
    if NEW in text:
        print(f"ok: {target} already carries the guard")
        return 0
    if OLD not in text:
        print(f"error: could not locate the insertion point in {target}",
              file=sys.stderr)
        return 1
    target.write_text(text.replace(OLD, NEW, 1))
    print(f"ok: applied the operator-only guard to {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())