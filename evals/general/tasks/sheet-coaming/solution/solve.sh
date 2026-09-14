#!/bin/bash
# Oracle for sheet-coaming: applies the upstream keyword-argument fix to the
# bandit checkout (/app/src/bandit/plugins/django_sql_injection.py), writes
# the /app/repro.py deliverable (a genuine, self-contained reproduction),
# verifies the reproduction passes on the repaired tree, and runs the
# upstream regression material (reconstructed from the pristine pre-fix tree)
# plus the project's own suite.
set -e

python3 /solution/fix_plugin.py /app/src/bandit/plugins/django_sql_injection.py

cat > /app/repro.py <<'PY'
#!/usr/bin/env python3
"""Reproduction: bandit logs an internal error for a keyword-argument
Django raw-SQL call and never reports the risky call.

Creates a small Python source file that exercises Django's raw-SQL expression
helper with the SQL text passed as a keyword argument, scans it with the
installed bandit, prints everything bandit wrote, and exits 0 only when
bandit's stderr contains no "Bandit internal error" line.  Works from any
current working directory and takes no arguments.
"""
import os
import subprocess
import sys
import tempfile

TRIGGER = (
    "from django.db.models.expressions import RawSQL\n"
    "from django.contrib.auth.models import User\n"
    "User.objects.annotate(val=RawSQL(sql='{}secure'.format('no'), params=[]))\n"
)


def main() -> int:
    fd, path = tempfile.mkstemp(suffix=".py", prefix="sc_repro_")
    try:
        with os.fdopen(fd, "w") as fh:
            fh.write(TRIGGER)
        result = subprocess.run(
            [sys.executable, "-m", "bandit", path],
            capture_output=True,
            text=True,
        )
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    if "internal error" in result.stderr:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY
chmod +x /app/repro.py

echo "== reproduction output after the fix =="
python3 /app/repro.py
echo "reproduction exit code: $?"

echo "== upstream regression material =="
rm -rf /tmp/grun
cp -a /app/src /tmp/grun
cd /tmp/grun
# No fix-commit bytes exist in the image: reconstruct the fix-commit revision
# of the regression material byte-exactly from the pristine parent tree at
# /opt/pretree (the fix commit added the two keyword-argument calls and raised
# the expected Medium count from 4 to 6).
python3 - /opt/pretree /tmp/golden-test.py <<'PY'
import re, sys
pretree, out = sys.argv[1], sys.argv[2]
src = open(pretree + "/" + "tests" + "/functional/test_functional.py").read()
start = src.index("    def test_django_sql_injection_raw")
m = re.search(r"\n    def ", src[start + 1:])
end = start + 1 + m.start() if m else len(src)
seg = src[start:end]
old = ('            "SEVERITY": {"UNDEFINED": 0, "LOW": 0, "MEDIUM": 4, "HIGH": 0},\n'
       '            "CONFIDENCE": {"UNDEFINED": 0, "LOW": 0, "MEDIUM": 4, "HIGH": 0},')
new = ('            "SEVERITY": {"UNDEFINED": 0, "LOW": 0, "MEDIUM": 6, "HIGH": 0},\n'
       '            "CONFIDENCE": {"UNDEFINED": 0, "LOW": 0, "MEDIUM": 6, "HIGH": 0},')
assert old in seg, "parent regression test shape not found"
open(out, "w").write(src[:start] + seg.replace(old, new) + src[end:])
PY
cp /opt/pretree/examples/django_sql_injection_raw.py /tmp/golden-example.py
cat >> /tmp/golden-example.py <<'EOF'
User.objects.annotate(val=RawSQL(sql='{}secure'.format('no'), params=[]))
User.objects.annotate(val=RawSQL(params=[], sql='{}secure'.format('no')))
EOF
test "$(sha256sum /tmp/golden-test.py | cut -d' ' -f1)" = \
     "ca42f12021717da9daaacb620403ffe5ec9b1680f50820db8596a2af43660914"
test "$(sha256sum /tmp/golden-example.py | cut -d' ' -f1)" = \
     "4d04b972eaf70c7076ffee0c556d6af93bf2ab8427da78d2f64efb35a2afae61"
cp /tmp/golden-test.py tests/functional/test_functional.py
cp /tmp/golden-example.py examples/django_sql_injection_raw.py
python3 -m stestr run --concurrency 1 \
  tests.functional.test_functional.FunctionalTests.test_django_sql_injection_raw

echo "== the project's own suite =="
cd /app/src
python3 -m stestr run --concurrency 1

echo "== oracle done =="