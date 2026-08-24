#!/bin/bash
# Oracle solution for item-026-hard.
set -euo pipefail
cd /app
git config user.email "dev@bench.test" >/dev/null 2>&1 || true
git config user.name "Dev" >/dev/null 2>&1 || true

# Minimal safe patch: sanitize at the response-header boundary in cookies.build.
cat > service/cookies.py <<'PY'
"""Cookie header construction. The HTTP response-header security boundary lives
here: `build` returns the value written into the `Set-Cookie` response header.

CWE-93: `payload` is attacker-influenced. CR/LF must never appear in the value
or a client can split the response and inject an arbitrary header.
"""
import re

_CRLF = re.compile(r'[\r\n]+')


def build(payload, flag):
    """Return a single-line Set-Cookie header value (never contains CR/LF)."""
    safe = _CRLF.sub('', payload or '')
    return "%s; HttpOnly; %s" % (safe, flag)
PY

# Add a small extra regression assertion beyond the shipped ones.
cat > tests/test_extra_regression.py <<'PY'
import sys
sys.path.insert(0, '/app')
from service import cookies


def test_fuzz_no_crlf_anywhere():
    for idx in range(0, 12):
        payload = 'uid=A' + ('X' * idx) + '\r\nSet-Cookie: owned=1'
        out = cookies.build(payload, 'strict')
        assert '\r' not in out and '\n' not in out
    for payload in ['a\nb', 'a\rb', 'a\r\nb\r\n', '\r\n']:
        out = cookies.build(payload, 'strict')
        assert '\r' not in out and '\n' not in out
PY

# Run the whole suite (shipped + newly added).
python3 -m pytest /app -q

# Commit source fix + added test.
git add -A
git commit -q -m "fix: strip CR/LF at cookies.build Set-Cookie boundary; add regression test"

echo "SOLVED"