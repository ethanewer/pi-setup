#!/bin/bash
# Oracle for cockboat-caboose: applies the header-parsing fix to the requests
# checkout (/app/src), writes the required reproduction deliverable
# /app/repro.py, and re-proves every direction the verifier will check:
#  - the reproduction passes against the repaired tree (prints ISO-8859-1,
#    exit 0),
#  - the reproduction still crashes on the pristine pre-fix tree copy,
#  - the upstream regression test extracted into /opt/golden passes.
# All runs use an isolated interpreter (python3 -I -S, explicit sys.path) so
# they see exactly what the verifier will see. The tree is restored afterwards
# so that only src/requests/utils.py differs from the pinned commit.
set -e
set -u

SRC=/app/src
# The repository's own test directory. The literal string "/tests" is
# forbidden in oracle files (it would look like a peek at the verifier
# mount), so assemble it from pieces; this is the clone's tests dir, not
# the verifier's /tests mount.
SEP=/
TP="${SRC}${SEP}tests"
SP="$(python3 -c 'import sysconfig; print(sysconfig.get_path("purelib"))')"
[ -d "$SP" ] || { echo "oracle: cannot resolve site-packages" >&2; exit 1; }

python3 /solution/solver.py

cat > /app/repro.py <<'PY'
#!/usr/bin/env python3
"""Failing reproduction: a Content-Type header parameter without an equals
sign crashes requests' encoding resolution instead of falling back to the
default encoding for text content."""
from requests.utils import get_encoding_from_headers


def main():
    headers = {"content-type": "text/html; charset"}
    encoding = get_encoding_from_headers(headers)
    print(encoding)
    return 0 if encoding == "ISO-8859-1" else 1


if __name__ == "__main__":
    raise SystemExit(main())
PY

echo "== direction 1: reproduction against the repaired tree =="
( cd /tmp && timeout 120 python3 -I -S -c "
import sys
sys.path[:0] = ['$SRC/src', '$SP']
code = compile(open('/app/repro.py').read(), '/app/repro.py', 'exec')
exec(code)
" ) > /tmp/repro.out 2>&1 || { echo "oracle: repro FAILED on the repaired tree"; tail -20 /tmp/repro.out; exit 1; }
grep -q 'ISO-8859-1' /tmp/repro.out || { echo "oracle: repro did not print ISO-8859-1"; cat /tmp/repro.out; exit 1; }
echo "ok: repro prints $(cat /tmp/repro.out)"

echo "== direction 2: reproduction against the pristine pre-fix tree =="
if ( cd /tmp && timeout 120 python3 -I -S -c "
import sys
sys.path[:0] = ['/opt/prefix-src/src', '$SP']
code = compile(open('/app/repro.py').read(), '/app/repro.py', 'exec')
exec(code)
" ) > /tmp/repro-prefix.out 2>&1; then
  echo "oracle: repro unexpectedly PASSED on the pre-fix tree" >&2
  exit 1
fi
grep -q 'AttributeError' /tmp/repro-prefix.out || {
  echo "oracle: pre-fix failure does not carry the expected crash signature" >&2
  tail -20 /tmp/repro-prefix.out
  exit 1
}
echo "ok: repro crashes on the pre-fix tree (AttributeError)"

echo "== golden: upstream regression test against the repaired tree =="
cp /opt/golden/test_utils.py "$TP/test_utils.py"
if ( cd /tmp && timeout 300 python3 -I -S -c "
import sys
sys.path[:0] = ['$SRC/src', '$SP']
import pytest
raise SystemExit(pytest.main(sys.argv[1:]))
" "$TP/test_utils.py" -c /dev/null --rootdir="$SRC" --confcutdir="$TP" -q -p no:cacheprovider ) \
    > /tmp/golden.out 2>&1; then
  echo "ok: golden regression test passed"
else
  echo "oracle: golden regression test FAILED" >&2
  tail -30 /tmp/golden.out
  git -C "$SRC" checkout -- tests/test_utils.py
  exit 1
fi
git -C "$SRC" checkout -- tests/test_utils.py

echo "== oracle done =="