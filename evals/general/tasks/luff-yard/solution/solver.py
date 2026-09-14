#!/usr/bin/env python3
"""Oracle solver for luff-yard: apply the upstream fix for the
WWW-Authenticate trailing-space defect to the werkzeug checkout at /app/src
and write the reproduction deliverable /app/reproduce_www_authenticate_bug.py.

The real work: the no-parameter early return is missing from
WWWAuthenticate.to_header, so a challenge with neither parameters nor a
token falls through to the parameter join/dump path, which appends a
trailing space. The fix inserts the guard between the token branch and the
digest branch. Note the token branch appears in BOTH Authorization.to_header
and WWWAuthenticate.to_header; the guard must land in the WWWAuthenticate
one, which is the one followed by the digest branch.
"""
import sys
from pathlib import Path

SRC = Path("/app/src/src/werkzeug/datastructures/auth.py")
REPRO = Path("/app/reproduce_www_authenticate_bug.py")

TOKEN_RETURN = (
    '        if self.token is not None:\n'
    '            return f"{self.type.title()} {self.token}"\n'
    '\n'
    '        if self.type == "digest":\n'
)
GUARDED = (
    '        if self.token is not None:\n'
    '            return f"{self.type.title()} {self.token}"\n'
    '\n'
    '        if not self.parameters:\n'
    '            return self.type.title()\n'
    '\n'
    '        if self.type == "digest":\n'
)

s = SRC.read_text()
if s.count(TOKEN_RETURN) != 1:
    sys.exit(f"solver: unexpected source shape in {SRC} (anchor count {s.count(TOKEN_RETURN)})")

if GUARDED not in s:
    s = s.replace(TOKEN_RETURN, GUARDED, 1)
    SRC.write_text(s)

REPRO.write_text(
    """#!/usr/bin/env python3
\"\"\"Reproduce the WWW-Authenticate trailing-space defect.

Exits 0 when the header serializes correctly; exits with a non-zero status
while the defect is present.
\"\"\"
import sys

from werkzeug.datastructures import WWWAuthenticate

h = WWWAuthenticate("bearer").to_header()
expected = "Bearer"
if h != expected:
    print("DEFECT PRESENT: WWWAuthenticate('bearer').to_header() = %r (expected %r)" % (h, expected))
    sys.exit(1)
print("ok: WWWAuthenticate('bearer').to_header() = %r" % (h,))
sys.exit(0)
"""
)
REPRO.chmod(0o755)

print("solver: fix applied and deliverables written")