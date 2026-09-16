"""Hidden case: without the typing extension loaded, the same files are fine.

The crash is specific to the typing extension's checking path. This guard runs
Pylint on the crashing shapes from a working directory where the project's own
pylintrc is not discovered and without --load-plugins, so the extension is
inactive: the file must lint normally (no crash, no fatal-error report), both
before and after any fix.
"""

import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
FIXTURE = str(HERE / "fixture_no_extension.py")

# Deliberately NOT /app/src: the project's pylintrc there enables the typing
# extension, which is exactly what this guard must be free of.
NEUTRAL_CWD = "/tmp"


def run_pylint_without_extension() -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, "-m", "pylint", FIXTURE,
         "--disable=useless-suppression", "--score=n"],
        cwd=NEUTRAL_CWD,
        capture_output=True,
        text=True,
        timeout=180,
    )


def test_no_extension_no_crash_no_fatal_error():
    r = run_pylint_without_extension()
    out = (r.stdout or "") + (r.stderr or "")
    assert "Fatal error" not in out, out
    assert "IndexError" not in out, out
    assert r.returncode != 1, "pylint reported a fatal error, exit status %d" % r.returncode


def test_extension_would_crash_without_fix_guard():
    # prove the fixture would actually crash the buggy extension, so this
    # guard is measuring the right thing: run once WITH the extension loaded
    # from a neutral cwd; a fixed tree must be clean even here.
    r = subprocess.run(
        [sys.executable, "-m", "pylint", FIXTURE,
         "--disable=all", "--enable=unnecessary-default-type-args",
         "--load-plugins=pylint.extensions.typing", "--score=n"],
        cwd=NEUTRAL_CWD,
        capture_output=True,
        text=True,
        timeout=180,
    )
    out = (r.stdout or "") + (r.stderr or "")
    assert "Fatal error" not in out, out
    assert "IndexError" not in out, out
    assert r.returncode == 0, "pylint exit status %d, output:\n%s" % (r.returncode, out)