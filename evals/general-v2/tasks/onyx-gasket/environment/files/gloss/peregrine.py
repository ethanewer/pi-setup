#!/usr/bin/env python3
"""Offscreen-GL loader used by the Hailshot platform's render preview path.

It searches only the directories listed in the ``$HAILSHOT_GL_LIB`` env var
(colon separated, empty entries ignored) and then the fixed directory
``/opt/hailshot/gl/lib``, looking for a ``libOSMesa`` shared object.  It never
falls back to ``ldconfig``.  On success it prints ``HAILSHOT_GL_OK`` and exits
0; it is what the platform's self-test calls to prove the interpreter can reach
the OSMesa runtime.
"""

import ctypes
import os
import sys

LIB_NAMES = ("libOSMesa.so", "libOSMesa.so.8", "libOSMesa.so.6")
FIXED_DIR = "/opt/hailshot/gl/lib"


def candidate_dirs():
    env = os.environ.get("HAILSHOT_GL_LIB", "")
    dirs = [d for d in env.split(":") if d]
    dirs.append(FIXED_DIR)
    return dirs


def find_lib():
    for d in candidate_dirs():
        for name in LIB_NAMES:
            p = os.path.join(d, name)
            if os.path.isfile(p):
                return p
    return None


def main():
    path = find_lib()
    if not path:
        print(
            "HAILSHOT_GL_ERR: no libOSMesa in %s" % candidate_dirs(),
            file=sys.stderr,
        )
        return 1
    try:
        ctypes.CDLL(path)
    except OSError as exc:  # pragma: no cover - only on a broken library
        print("HAILSHOT_GL_ERR: %s" % exc, file=sys.stderr)
        return 1
    if not os.path.basename(path).startswith("libOSMesa"):
        print("HAILSHOT_GL_ERR: %s is not OSMesa" % path, file=sys.stderr)
        return 1
    print("HAILSHOT_GL_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())