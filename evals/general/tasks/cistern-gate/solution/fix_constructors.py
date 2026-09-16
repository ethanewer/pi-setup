#!/usr/bin/env python3
"""Fix pip's requirement-line constructor.

The bug: parse_req_from_line() in src/pip/_internal/req/constructors.py wraps
the requirement part in try/except (InvalidRequirement -> InstallationError)
but calls Marker(markers_as_string) unguarded, so an invalid marker section
leaks pip._vendor.packaging.markers.InvalidMarker as a raw traceback.

The fix: wrap the Marker() construction in the same way and convert
InvalidMarker into a clean InstallationError("Invalid requirement: ...") that
names the offending requirement.

Usage: fix_constructors.py [path-to-constructors.py]
"""
import pathlib
import sys

DEFAULT = "/app/src/src/pip/_internal/req/constructors.py"

IMPORT_OLD = "from pip._vendor.packaging.markers import Marker\n"
IMPORT_NEW = "from pip._vendor.packaging.markers import InvalidMarker, Marker\n"

GUARD_OLD = """        else:
            markers = Marker(markers_as_string)
"""
GUARD_NEW = """        else:
            try:
                markers = Marker(markers_as_string)
            except InvalidMarker as exc:
                raise InstallationError(f"Invalid requirement: {name.strip()!r}: {exc}")
"""


def main() -> int:
    path = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else DEFAULT)
    src = path.read_text()
    if IMPORT_OLD not in src:
        print(f"error: expected import line not found in {path}", file=sys.stderr)
        return 1
    if src.count(GUARD_OLD) != 1:
        print("error: expected marker-construction block not found exactly once",
              file=sys.stderr)
        return 1
    src = src.replace(IMPORT_OLD, IMPORT_NEW).replace(GUARD_OLD, GUARD_NEW)
    path.write_text(src)
    print(f"fixed {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())