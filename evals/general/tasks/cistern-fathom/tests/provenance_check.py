#!/usr/bin/env python3
"""cistern-fathom provenance guard.

The agent's deliverable is the repaired upstream checkout at /app/src. This
script asserts the repository state the task contract requires:

  * HEAD is still the pinned parent revision (the agent must not move it);
  * the upstream fix commit object is NOT in the object store (the agent must
    not have fetched/checked it out -- and the image never shipped it);
  * the only tracked change, staged or unstaged, is the single library source
    file the fix requires, and that file IS changed (a fix was delivered);
  * no stray untracked files were added inside the repository tree (build
    artifacts like __pycache__ / *.pyc / *.egg-info / .pytest_cache are OK).

Any violation -> exit 1 (the verifier scores 0).
"""
import os
import re
import subprocess
import sys

REPO = "/app/src"
PARENT = "4c09d1b3b08deb939803a4beb53483cbc54dfb8d"
FIX = "f516c4005c7c4510b61ae07969450771b929809d"
SRC = "src/werkzeug/datastructures/structures.py"
ARTIFACT = re.compile(r"(^|/)(__pycache__/|.*\.pyc$|.*\.egg-info/|\.pytest_cache/)")


def sh(*args):
    return subprocess.run(args, cwd=REPO, capture_output=True, text=True)


def err(msg):
    print(f"cistern-fathom provenance FAIL: {msg}", file=sys.stderr)
    return False


ok = True

if not os.path.isfile(os.path.join(REPO, SRC)):
    ok = err(f"missing {SRC}: the checkout is not as expected")
    sys.exit(0 if ok else 1)

head = sh("git", "rev-parse", "HEAD")
if head.returncode != 0:
    ok = err("not a git repository: git rev-parse failed")
else:
    cur = head.stdout.strip()
    if cur != PARENT:
        ok = err(f"repository HEAD moved from {PARENT} to {cur}")

if sh("git", "cat-file", "-e", f"{FIX}^{{commit}}").returncode == 0:
    ok = err("upstream fix commit object is present in the object store")

staged = sh("git", "diff", "--cached", "--name-only").stdout.split()
for f in staged:
    if f != SRC:
        ok = err(f"staged change outside the fix: {f}")

changed = sh("git", "diff", "HEAD", "--name-only").stdout.split()
for f in changed:
    if f != SRC:
        ok = err(f"tracked change outside the fix: {f}")
if SRC not in changed:
    ok = err("no change delivered to the library source (the fix must modify it)")

status = sh("git", "status", "--porcelain", "--untracked-files=normal")
for line in status.stdout.splitlines():
    if line.startswith("?? "):
        p = line[3:]
        if not ARTIFACT.search(p):
            ok = err(f"untracked file inside the repository tree: {p}")

# The fix must exist IN THE SOURCE BYTES of the deliverable, not in the
# interpreter environment. A wrapper planted somewhere outside the tree
# (e.g. a sitecustomize.py that monkeypatches TypeConversionDict.get at
# startup) can make every behavioural check pass while the actual library
# file is untouched; the git checks above only prove the file was *touched*.
# So require the converter guard in TypeConversionDict.get to absorb
# TypeError as well as ValueError -- that is exactly the upstream repair.
src_text = open(os.path.join(REPO, SRC), encoding="utf-8").read()
m = re.search(r"rv = type\(rv\)\s*\n\s*except ([^:]+):", src_text)
if not m:
    ok = err("fix not in source: no except clause guards the converter call in TypeConversionDict.get")
elif "TypeError" not in m.group(1):
    ok = err("fix not in source: the converter guard must absorb TypeError as well as ValueError")

sys.exit(0 if ok else 1)