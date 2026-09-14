#!/usr/bin/env python3
"""Real solver for chandlery-waypoint (flake8 crash when $HOME does not exist).

This mirrors the honest workflow the task asks of an agent:

1. write the failing reproduction as the deliverable
   /app/reproduce_unknown_homedir.py (a crash-first reproduction: flake8 dies
   with a FileNotFoundError traceback before doing any work when $HOME names a
   directory that does not exist);
2. repair the config-discovery step in the real checkout at /app/src: the
   expanded home path is stat'ed unguarded, so any home that cannot be stat'ed
   (missing, permission-denied, ...) kills flake8 at startup; the fix treats an
   un-stat-able home exactly like an unset home (home_stat = None) and lets
   discovery continue;
3. self-check: the reproduction now exits 0 and the project's own
   tests/unit/test_options_config.py still passes.

The reproduction reaches flake8 through the interpreter's normal module
resolution (PYTHONPATH or the editable install), never through hard-coded
imports of /app/src, so the grader can re-run it against the pristine tree.
"""
import os
import subprocess
import sys

CONFIG = "{src}/src/flake8/options/config.py"

REPRO_BODY = """#!/usr/bin/env python3
\"\"\"Reproduction: flake8 crashes before linting when $HOME does not exist.

A raw Python traceback ending in ``FileNotFoundError`` for the missing home
directory is emitted and no lint output is produced. This script drives the
command-line entry point exactly like a user would, in a process whose HOME
points at a directory that does not exist. It reaches flake8 through the
interpreter's normal module resolution, so the same script demonstrates the
crash against the unfixed tree and exits 0 against a fixed one.
\"\"\"
import os
import subprocess
import sys

os.environ["HOME"] = "/nonexistent-home-directory-for-flake8"

proc = subprocess.run(
    [sys.executable, "-m", "flake8", "--version"],
    env=dict(os.environ),
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)

if proc.returncode == 0:
    sys.exit(0)  # flake8 started and printed its version: the bug is fixed
else:
    sys.stderr.write(proc.stderr or proc.stdout or "flake8 failed\\n")
    sys.exit(1)
"""


def main() -> int:
    if len(sys.argv) >= 3:
        src, repro = sys.argv[1], sys.argv[2]
    else:
        src, repro = "/app/src", "/app/reproduce_unknown_homedir.py"
    config_path = CONFIG.format(src=src)

    # ---- 1. write the reproduction deliverable --------------------------------
    with open(repro, "w") as fh:
        fh.write(REPRO_BODY)
    os.chmod(repro, 0o755)
    print("wrote", repro)

    # ---- 2. apply the minimal fix ----------------------------------------------
    src_text = open(config_path).read()
    old = '    home_stat = _stat_key(home) if home != "~" else None\n'
    if src_text.count(old) != 1:
        print("expected exactly one buggy home-stat line in", config_path, file=sys.stderr)
        return 1
    new = (
        "    try:\n"
        "        home_stat = _stat_key(home) if home != \"~\" else None\n"
        "    except OSError:  # FileNotFoundError / PermissionError / etc.\n"
        "        home_stat = None\n"
    )
    open(config_path, "w").write(src_text.replace(old, new))
    print("patched", config_path)

    # ---- 3. self-check: reproduction exits 0, project config tests pass -------
    env = dict(os.environ)
    env["HOME"] = "/nonexistent-home-directory-for-flake8"
    env["PYTHONPATH"] = src + "/src"
    check = subprocess.run(
        [sys.executable, repro], env=env, capture_output=True, text=True
    )
    if check.returncode != 0:
        print("self-check: reproduction still fails after the fix", file=sys.stderr)
        print(check.stderr[-2000:], file=sys.stderr)
        return 1
    print("self-check: reproduction exits 0 against the fixed tree")

    pytest_env = dict(os.environ)
    pytest_env["PYTHONPATH"] = src + "/src"
    tests = subprocess.run(
        [sys.executable, "-m", "pytest", "tests/unit/test_options_config.py", "-q"],
        cwd=src, env=pytest_env, capture_output=True, text=True,
    )
    if tests.returncode != 0:
        print("self-check: project config tests failed", file=sys.stderr)
        print((tests.stdout + tests.stderr)[-2000:], file=sys.stderr)
        return 1
    print("self-check: tests/unit/test_options_config.py passes")
    return 0


if __name__ == "__main__":
    sys.exit(main())