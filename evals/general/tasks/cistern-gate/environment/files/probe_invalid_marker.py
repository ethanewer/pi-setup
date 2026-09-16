#!/usr/bin/env python3
"""Probe for the invalid-marker bug in the checked-out pip tree at /app/src.

Valid requirement lines parse; invalid marker sections leak an internal
pip._vendor.packaging.markers.InvalidMarker traceback instead of being
reported as an invalid requirement.
"""
import traceback

import pip
from pip._internal.req.constructors import install_req_from_line


def main() -> None:
    print("import pip ->", pip.__file__)
    print()
    for line in [
        'name; python_version == "1"; python_version == "2"',
        'pkg; extra == "a"; python_version > "3.12"',
        "foo; python_version == '3",
    ]:
        try:
            req = install_req_from_line(line)
            print(f"{line!r}: parsed OK -> {req}")
        except Exception as exc:  # noqa: BLE001 - probe must not die
            print(f"{line!r}: RAISED {type(exc).__module__}.{type(exc).__name__}")
            print("   message:", str(exc).splitlines()[0])
            print("   (traceback follows)")
            traceback.print_exc(limit=4)
    print()
    req = install_req_from_line('ok; python_version == "3.12"')
    print("valid marker still parses: str(markers) =", str(req.markers))


if __name__ == "__main__":
    main()