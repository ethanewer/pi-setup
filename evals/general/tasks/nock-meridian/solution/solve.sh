#!/bin/bash
# Oracle for nock-meridian: fixes pip's double percent-decoding of the URL
# basename inside the pinned checkout at /app/src, byte-identically to the
# upstream fix for issue #14110, and writes the failing-reproduction
# deliverable /app/reproduce.py.
# It NEVER reads /tests.
set -euo pipefail

SRC=/app/src
INT="$SRC/src/pip/_internal"

# 1) Apply the fix: Link.filename must not percent-decode the basename a
#    second time (_path is already decoded once), the derived name must stay
#    a single path component, and the download/prepare joins must use it as
#    one component. fix_pip.py anchors every edit on the pinned parent bytes
#    and fails loudly if the checkout ever drifts.
python3 /solution/fix_pip.py "$INT"

# 2) Write the failing-reproduction deliverable: a self-contained script that
#    imports pip from whatever checkout it is handed, derives the file name
#    for a doubly-encoded URL, prints it, and exits 0 iff the name is a single
#    path component.
cat > /app/reproduce.py <<'PY'
#!/usr/bin/env python3
"""Failing reproduction for pip's double-decoded URL file-name bug.

Contract (nock-meridian):
  python3 reproduce.py [checkout-dir]
    - derives the local file name pip would store for a doubly-encoded URL,
      using the pip checkout at <checkout-dir> (package in <checkout>/src);
    - prints exactly one line:  FILENAME: <derived name>
    - exits 0 if and only if the derived name is a single path component
      (no '/', equals its own basename, not empty/dot/dotdot); else exits 1.
On the original buggy checkout the derived name collapses the double-encoded
separator into a real '/' and this script exits 1; on a corrected pip the
name keeps the literal escape and this script exits 0.
"""
import os
import posixpath
import sys

URL = "https://example.com/a%252Fb.whl"


def is_single_component(name: str) -> bool:
    if "/" in name:
        return False
    if posixpath.basename(name) != name:
        return False
    return name not in ("", ".", "..")


def main() -> int:
    checkout = sys.argv[1] if len(sys.argv) > 1 else "/app/src"
    sys.path.insert(0, os.path.join(checkout, "src"))

    from pip._internal.models.link import Link  # noqa: E402

    name = Link(URL).filename
    print(f"FILENAME: {name}")
    return 0 if is_single_component(name) else 1


if __name__ == "__main__":
    sys.exit(main())
PY
chmod +x /app/reproduce.py

# 3) Prove the reproduction is a genuine failing repro in both directions:
#    on a pristine copy of the pinned (buggy) commit it must FAIL, on the
#    repaired tree it must PASS.
rm -rf /tmp/oracle-pristine
mkdir -p /tmp/oracle-pristine
git -C "$SRC" archive "$(git -C "$SRC" rev-parse HEAD)" | tar -x -C /tmp/oracle-pristine
if python3 /app/reproduce.py /tmp/oracle-pristine; then
    echo "ERROR: reproduction passed on the pristine buggy tree" >&2
    exit 1
fi
if ! python3 /app/reproduce.py "$SRC"; then
    echo "ERROR: reproduction failed on the repaired tree" >&2
    exit 1
fi
rm -rf /tmp/oracle-pristine

# 4) The project's own regression test for this bug (extracted from the fix
#    commit into /opt/golden) and a slice of the existing unit suite that
#    covers the same code area must both pass.
cd "$SRC"
PYTHONPATH=src python3 -m pytest -q -o addopts= -p no:cacheprovider \
    /opt/golden/test_link.py
PYTHONPATH=src python3 -m pytest -q -o addopts= -p no:cacheprovider \
    tests/unit/test_link.py tests/unit/test_operations_prepare.py

echo "nock-meridian oracle done"