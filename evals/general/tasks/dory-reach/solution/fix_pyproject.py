#!/usr/bin/env python3
"""Fix trivy's PEP 621 pyproject.toml parser so dependency names are normalized.

`Dependencies.UnmarshalTOML()` handles the `[project].dependencies` list form
(Poetry v2 / PEP 621) by stripping version operators and taking the first
field as the package name, then appending it to the dependency set EXACTLY as
typed. A manifest that spells a name non-canonically ("Flask",
"typing_extensions", "ruamel.yaml") therefore reports that spelling, while the
poetry/pylock parsers (and the map form of the same function) report the
PEP 503 normalized spelling ("flask", "typing-extensions", "ruamel-yaml").
The same package then appears under two spellings in one scan and manifest
names never match the normalized lockfile names.

The fix passes the extracted name through `python.NormalizePkgName(name, true)`
(after the same normalization the map branch of this very function already
applies), so `Flask` -> `flask`, `typing_extensions` -> `typing-extensions`
and `ruamel.yaml` -> `ruamel-yaml`. This is exactly what upstream commit
0012281c8a8adad2eff1889f12fe08a0ca5a7bfc (issue #11050) does.

Usage: fix_pyproject.py [path-to-pyproject.go]
"""
import pathlib
import sys

DEFAULT = "/app/src/pkg/dependency/parser/python/pyproject/pyproject.go"

OLD = "\t\t\td.Set.Append(strings.Fields(dep)[0]) // Save only name"
NEW = "\t\t\td.Set.Append(python.NormalizePkgName(strings.Fields(dep)[0], true)) // Save only name"


def main() -> int:
    target = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else DEFAULT)
    text = target.read_text()
    if NEW in text:
        print(f"ok: {target} already carries the normalization")
        return 0
    if OLD not in text:
        print(f"error: could not locate the insertion point in {target}",
              file=sys.stderr)
        return 1
    target.write_text(text.replace(OLD, NEW, 1))
    print(f"ok: applied PEP 503 name normalization to {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())