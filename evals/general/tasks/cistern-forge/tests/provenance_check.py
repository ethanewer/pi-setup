#!/usr/bin/env python3
"""cistern-forge provenance guard.

The agent's deliverable is the repaired upstream checkout at /app/src. This
script asserts the repository state the task contract requires:

  * HEAD is still the pinned parent revision (the agent must not move it);
  * the upstream fix and regression-test commit objects are NOT in the object
    store (the agent must not have fetched/checked them out -- and the image
    never shipped them); the object store holds exactly one commit;
  * the only tracked change, staged or unstaged, is the single library source
    file the fix requires, and that file IS changed (a fix was delivered);
  * no stray untracked files were added inside the repository tree (build
    artifacts like __pycache__ / *.pyc / *.egg-info / .pytest_cache / the
    editable-install egg-info are OK);
  * the installed `psycopg` package resolves into /app/src;
  * source-integrity gate: the two-phase repro is re-run under `python3 -S -P`
    (site machinery and cwd shadowing disabled, typing_extensions staged at
    /opt/checkdeps with a pinned SHA-256) so that the loaded psycopg.waiting
    is the real /app/src source and it ALONE must make the repro complete --
    out-of-tree behaviour shims (sitecustomize.py / *.pth / edited
    site-packages modules / a fake /tmp package) cannot satisfy it.

Any violation -> exit 1 (the verifier scores 0).
"""
import os
import re
import subprocess
import sys

REPO = "/app/src"
PARENT = "f9078032c2ccd64ec351b3ab7bdeb257b2480977"
FORBIDDEN_COMMITS = [
    "b9f196895eb6d3973437102fb50802266dedafea",  # upstream fix (wait_selector)
    "f46aad6461e6f403b8dea0e59860835b9fdc0f16",  # same branch: wait_conn perf fix
    "5369bbc9286f94cc2ed983288a607082e60f0371",  # same branch: regression tests
    "3407a9614c6427090be6ec37c067f58d02abe98b",  # same branch: merge
]
SRC = "psycopg/psycopg/waiting.py"
ARTIFACT = re.compile(
    r"(^|/)(__pycache__/|.*\.pyc$|.*\.egg-info/|.*\.dist-info/|\.pytest_cache/)"
)

# The two-phase repro, run under `python3 -S` (no site-packages) so that
# out-of-tree behaviour shims (sitecustomize.py / .pth / edited site-packages
# modules) cannot satisfy it: the loaded psycopg.waiting must be the real
# /app/src source and it alone must survive a generator that waits twice on
# the same fd (the connect-style write-then-read flow that crashes the
# unfixed parent with KeyError '... is already registered').
#
# -S drops typing_extensions (psycopg's only runtime dep on 3.12) from
# sys.path, so a pinned copy staged at /opt/checkdeps is appended; its
# SHA-256 is verified below so tampering with the check dependency cannot
# disable the gate.
CHECKDEPS_FILE = "/opt/checkdeps/typing_extensions.py"
CHECKDEPS_SHA256 = "4040ca1a1ecbee00d1385c12a93084d1c5bd46f0b774f07e5ae7e91c4f55e696"

SOURCE_REPRO = r'''
import socket, selectors
from psycopg import waiting
assert waiting.__file__.startswith("/app/src/psycopg/"), \
    f"psycopg.waiting resolved to {waiting.__file__}, not /app/src/psycopg/"
r, w = socket.socketpair()
def gen():
    yield selectors.EVENT_WRITE   # phase 1: wait until writable
    yield selectors.EVENT_READ    # phase 2: wait for read after wake-up
    return "COMPLETED"
try:
    rv = waiting.wait_selector(gen(), r.fileno(), interval=0.05)
    print("returned:", rv)
except Exception as ex:
    print(type(ex).__name__, "-", ex)
'''


def sh(*args):
    return subprocess.run(args, cwd=REPO, capture_output=True, text=True)


def err(msg):
    print(f"cistern-forge provenance FAIL: {msg}", file=sys.stderr)
    return False


ok = True

if not os.path.isdir(REPO):
    ok = err("missing /app/src: the task image is not as expected")
    sys.exit(0 if ok else 1)

head = sh("git", "rev-parse", "HEAD")
if head.returncode != 0:
    ok = err("not a git repository: git rev-parse failed")
else:
    cur = head.stdout.strip()
    if cur != PARENT:
        ok = err(f"repository HEAD moved from {PARENT} to {cur}")

for commit in FORBIDDEN_COMMITS:
    if sh("git", "cat-file", "-e", f"{commit}^{{commit}}").returncode == 0:
        ok = err(f"upstream commit object {commit} is present in the object store")

count = sh("git", "rev-list", "--all", "--count")
if count.returncode == 0:
    n = int(count.stdout.strip())
    if n != 1:
        ok = err(f"object store contains {n} commits, expected exactly 1 (only the parent)")

# The imported module must resolve into the deliverable tree.
import psycopg.waiting  # noqa: E402

wfile = os.path.realpath(psycopg.waiting.__file__)
if not wfile.startswith("/app/src/psycopg/"):
    ok = err(f"installed psycopg.waiting resolves to {wfile}, not under /app/src/psycopg/")
if not os.path.isfile(wfile):
    ok = err(f"installed psycopg.waiting file missing: {wfile}")

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

# --- source-integrity gate: the loaded source alone must fix the bug --------
# Runs the repro under `python3 -S` so no site-packages shim (sitecustomize,
# .pth, edited installed module) participates: the deliverable is the source.
import hashlib  # noqa: E402

if ok:
    try:
        with open(CHECKDEPS_FILE, "rb") as f:
            dep_sha = hashlib.sha256(f.read()).hexdigest()
        if dep_sha != CHECKDEPS_SHA256:
            ok = err(f"{CHECKDEPS_FILE} hash mismatch ({dep_sha[:12]}...), expected "
                     f"{CHECKDEPS_SHA256[:12]}...; the check dependency is tampered")
        env = dict(os.environ)
        env["PYTHONPATH"] = "/app/src/psycopg:/opt/checkdeps"
        # -S -P: skip the site machinery, and do not prepend cwd/script dir
        # to sys.path, so no /tmp shadow package can take import precedence;
        # PYTHONPATH is still honoured.
        proc = subprocess.run(
            [sys.executable, "-S", "-P", "-"],
            input=SOURCE_REPRO, capture_output=True, text=True, env=env,
            cwd="/tmp", timeout=60,
        )
        out = (proc.stdout + proc.stderr).strip()
        if "returned: COMPLETED" not in out:
            ok = err(f"source-integrity repro did not complete through the real "
                     f"/app/src source (rc={proc.returncode})\n--- output ---\n{out[-800:]}")
    except FileNotFoundError:
        ok = err(f"missing {CHECKDEPS_FILE}: cannot run the site-free source check")
    except subprocess.TimeoutExpired:
        ok = err("source-integrity repro timed out")

sys.exit(0 if ok else 1)