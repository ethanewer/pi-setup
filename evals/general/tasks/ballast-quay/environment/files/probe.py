#!/usr/bin/env python3
"""Probe for the implicit-str-concat raw/non-raw false positive.

Builds two temporary sample files and runs the installed pylint on each with
only the implicit-str-concat check enabled:

  * mixed.py   -- adjacent mixed raw/non-raw string literals, which must NOT
                 trigger W1404 (the two literals cannot be merged into one
                 literal, so the juxtaposition is deliberate), and
  * control.py -- adjacent plain (non-raw) string literals, which MUST still
                 trigger W1404 so we know the check was not simply disabled.

Exits 0 when both expectations hold for the installed pylint, 1 otherwise.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

MIXED = """\
MIXED_RAW1 = [r"\\d" "\\n"]
MIXED_RAW2 = "\\n" r"\\d"
MIXED_RAW3 = (r"\\override Stem" "\\n", "other")
MIXED_RAW4 = [R"\\S+" u"\\w+"]
MIXED_RAW5 = {r"[a-z]+" "[A-Z]+"}
MIXED_RAW6 = print(r"x" "y")
"""

CONTROL = """\
PLAIN1 = "a" "b"
PLAIN2 = ("x" "y", "z")
PLAIN3 = {"k": "v1" "v2"}
"""


def run_pylint(tmp: Path, name: str, src: str) -> subprocess.CompletedProcess:
    path = tmp / name
    path.write_text(src)
    return subprocess.run(
        [
            sys.executable,
            "-m",
            "pylint",
            str(path),
            "--disable=all",
            "--enable=implicit-str-concat",
            "--score=n",
        ],
        capture_output=True,
        text=True,
    )


def main() -> int:
    ok = True
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        mixed = run_pylint(tmp, "mixed.py", MIXED)
        plain = run_pylint(tmp, "control.py", CONTROL)

    print("--- mixed raw/non-raw literals ---")
    out = (mixed.stdout + mixed.stderr).strip()
    print(out if out else f"(no output; exit {mixed.returncode})")
    if mixed.returncode != 0 or "implicit-str-concat" in out:
        print("FAIL: mixed raw/non-raw concatenation is still reported",
              file=sys.stderr)
        ok = False
    else:
        print("ok: mixed raw/non-raw concatenation is not reported")

    print("--- control: plain concatenation ---")
    out = (plain.stdout + plain.stderr).strip()
    print(out if out else f"(no output; exit {plain.returncode})")
    if "implicit-str-concat" not in out:
        print("FAIL: plain concatenation control no longer reports W1404",
              file=sys.stderr)
        ok = False
    else:
        print("ok: plain concatenation is still reported")

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())