#!/bin/bash
# Oracle for barge-basin: applies the empty-subprocess-arg-list guard fix to
# the bandit checkout (/app/src/bandit/plugins/injection_shell.py), writes the
# /app/repro.py deliverable (a genuine, self-contained reproduction), verifies
# the reproduction passes on the repaired tree, and runs the upstream
# regression material extracted into /opt/golden/ at image build time.
set -e

python3 /solution/fix_injection_shell.py /app/src/bandit/plugins/injection_shell.py

cat > /app/repro.py <<'PY'
#!/usr/bin/env python3
"""Reproduction: bandit logs an internal error for an empty-list subprocess call.

Creates a small Python file that passes an empty list to a standard-library
subprocess helper, scans it with the installed bandit, prints everything
bandit wrote, and exits 0 only when bandit's stderr contains no
"Bandit internal error" line.  Works from any current working directory and
takes no arguments.
"""
import os
import subprocess
import sys
import tempfile

TRIGGER = (
    "import subprocess\n"
    "subprocess.check_output([], stdout=None)\n"
)


def main() -> int:
    fd, path = tempfile.mkstemp(suffix=".py", prefix="bb_repro_")
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
cp /opt/golden/test_functional.py tests/functional/test_functional.py
cp /opt/golden/subprocess_shell.py examples/subprocess_shell.py
python3 -m stestr run --concurrency 1 \
  tests.functional.test_functional.FunctionalTests.test_subprocess_shell

echo "== oracle done =="