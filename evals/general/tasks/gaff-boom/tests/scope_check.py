#!/usr/bin/env python3
"""Whole-repo scope check for gaff-boom.

The agent may modify exactly two tracked files (the two source files the
memory-zone bug lives in) and nothing else. This check compares the working
tree against the pinned parent commit byte-for-byte (via content hashes of
every tracked file), immune to assume-unchanged/skip-worktree/index tricks:

- every tracked file except the two allowed must be byte-identical to its
  parent blob (missing file, modified bytes, or a change hidden behind an
  assume-unchanged flag all fail),
- the two allowed files must each DIFFER from their parent blob (a no-op agent
  fails here),
- `git status --porcelain` must list exactly those two files as modified and
  no untracked files anywhere in the tree.
"""
import hashlib
import subprocess
import sys

REPO = "/app/src"
PARENT = "453732d32d55029ea9787ef737c8cf8d626f45b0"
ALLOWED = {"spacy/strings.pyx", "spacy/vocab.pyx"}


def git(args):
    return subprocess.run(
        ["git"] + args, capture_output=True, text=True, cwd=REPO
    )


def head_blob_sha(path):
    r = git(["rev-parse", f"{PARENT}:{path}"])
    if r.returncode != 0:
        return None
    blob = r.stdout.strip()
    c = subprocess.run(
        ["git", "cat-file", "-p", blob], capture_output=True, cwd=REPO
    )
    if c.returncode != 0:
        return None
    return hashlib.sha256(c.stdout).hexdigest()


def file_sha(path):
    try:
        with open(f"{REPO}/{path}", "rb") as f:
            return hashlib.sha256(f.read()).hexdigest()
    except FileNotFoundError:
        return None


errors = []

ls = git(["ls-files", "-z"])
for raw in ls.stdout.split("\0"):
    path = raw
    if not path:
        continue
    head_sha = head_blob_sha(path)
    if head_sha is None:
        errors.append(f"cannot resolve parent blob for {path}")
        continue
    wt_sha = file_sha(path)
    if wt_sha is None:
        errors.append(f"tracked file missing from working tree: {path}")
        continue
    if path in ALLOWED:
        if wt_sha == head_sha:
            errors.append(f"allowed source file unchanged: {path}")
    else:
        if wt_sha != head_sha:
            errors.append(f"unexpected modification outside allowed sources: {path}")

status = git(["status", "--porcelain"]).stdout
expected = {" M spacy/strings.pyx", " M spacy/vocab.pyx"}
actual = {line for line in status.splitlines() if line}
if actual != expected:
    errors.append(f"git status mismatch: {sorted(actual)} != {sorted(expected)}")

if errors:
    for e in errors:
        print("SCOPE-FAIL:", e)
    sys.exit(1)

print("SCOPE-OK: exactly the two allowed sources differ from the pinned commit")
sys.exit(0)