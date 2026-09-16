#!/usr/bin/env python3
"""Reproduction for the empty-tuple type-argument crash (oracle copy).

Contract (must also hold for /app/reproduce.py as written by the agent):
- creates a small source file containing a collections.abc.Generator[()]
  annotation and runs the installed Pylint on it with the typing extension
  enabled and the unnecessary-default-type-args check enabled;
- prints a short diagnostic;
- exits 0 iff Pylint completes without a fatal internal error;
- exits non-zero iff Pylint crashes with the fatal internal error.
"""

import subprocess
import sys
import tempfile
from pathlib import Path

SAMPLE = """# pylint: disable=missing-docstring,deprecated-typing-alias
import collections.abc as ca

x1: ca.Generator[()]
x2: ca.AsyncGenerator[()]
"""


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        sample = Path(tmp) / "sample.py"
        sample.write_text(SAMPLE)
        cmd = [
            sys.executable,
            "-m",
            "pylint",
            str(sample),
            "--disable=all",
            "--enable=unnecessary-default-type-args",
            "--load-plugins=pylint.extensions.typing",
            "--score=n",
        ]
        proc = subprocess.run(cmd, cwd="/app/src", capture_output=True, text=True)
        sys.stdout.write("pylint exit status: %d\n" % proc.returncode)
        if proc.stdout:
            sys.stdout.write(proc.stdout)
        if proc.stderr:
            sys.stderr.write(proc.stderr)
        crashed = (
            proc.returncode != 0
            and ("Fatal error" in proc.stdout or "IndexError" in proc.stderr)
        )
        if not crashed:
            print("RESULT: pylint completed without a fatal internal error")
            return 0
        print("RESULT: pylint crashed with a fatal internal error (bug reproduced)", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())