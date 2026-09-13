#!/usr/bin/env python3
"""Apply the minimal upstream fix to /app/src/cli/src/semgrep/git.py.

The parent commit's get_project_url() returns the output of
`git ls-remote --get-url` verbatim, leaking any credentials embedded in the
configured remote URL. The upstream fix (semgrep issue #9849) routes the
return value through a new module-level clean_project_url() that strips the
userinfo part of the netloc. This script reproduces that change in place:

  1. adds `import re` and `import urllib` to the import block;
  2. replaces the body of get_project_url() to call clean_project_url();
  3. inserts the clean_project_url() function before get_git_root_path().

It is idempotent and fails loudly (non-zero exit) if the tree no longer
matches the parent commit's expectations.
"""
import sys

PATH = "/app/src/cli/src/semgrep/git.py"

OLD_IMPORTS = """import os
import subprocess
import tempfile
from contextlib import contextmanager
"""
NEW_IMPORTS = """import os
import re
import subprocess
import tempfile
import urllib
from contextlib import contextmanager
"""

OLD_BODY = """    try:
        return git_check_output([\"git\", \"ls-remote\", \"--get-url\"])
    except Exception as e:
"""
NEW_BODY = """    try:
        remote_url = git_check_output([\"git\", \"ls-remote\", \"--get-url\"])
        return clean_project_url(remote_url)
    except Exception as e:
"""

ANCHOR = "def get_git_root_path() -> Path:"

HELPER = '''def clean_project_url(url: str) -> str:
    """
    Returns a clean version of a git project's URL, removing credentials if present
    """
    parts = urllib.parse.urlsplit(url)
    clean_netloc = re.sub("^.*:.*@(.+)", r"\\1", parts.netloc)
    parts = parts._replace(netloc=clean_netloc)
    return urllib.parse.urlunsplit(parts)


'''


def main() -> int:
    with open(PATH, encoding="utf-8") as f:
        src = f.read()

    if "def clean_project_url" in src:
        print("clarent: git.py already contains clean_project_url; nothing to do")
        return 0

    errors = []
    if OLD_IMPORTS not in src:
        errors.append("expected import block not found")
    if OLD_BODY not in src:
        errors.append("expected get_project_url body not found")
    if ANCHOR not in src:
        errors.append("expected get_git_root_path anchor not found")
    if errors:
        for e in errors:
            print(f"error: {e}", file=sys.stderr)
        return 1

    src = src.replace(OLD_IMPORTS, NEW_IMPORTS, 1)
    src = src.replace(OLD_BODY, NEW_BODY, 1)
    src = src.replace(ANCHOR, HELPER + ANCHOR, 1)

    for needle in ("import re\n", "import urllib\n",
                   "return clean_project_url(remote_url)",
                   "def clean_project_url(url: str) -> str:"):
        if needle not in src:
            print(f"error: postcondition not met: {needle!r}", file=sys.stderr)
            return 1

    with open(PATH, "w", encoding="utf-8") as f:
        f.write(src)
    print("applied clean_project_url fix to " + PATH)
    return 0


if __name__ == "__main__":
    sys.exit(main())