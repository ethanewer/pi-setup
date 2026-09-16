#!/usr/bin/env python3
"""Apply the ballast-fathom fix to a pristine git 2.21-era builtin/stash.c.

Root cause: in the built-in stash, `push_stash` parses the user pathspecs with
`parse_pathspec(&ps, 0, PATHSPEC_PREFER_FULL, prefix, argv)` and
`add_pathspecs()` pushes `ps.items[i].match` (the *parsed* form) into the argv
handed to the internal `git add` / `git diff-index` / `git ls-files` child
processes. When no PATHSPEC_PREFIX_ORIGIN is requested, `.match` strips the
magic prefix, so a glob such as ':(glob)**/*.txt' reaches the child as plain
'**/*.txt', which under normal (non-glob) pathspec matching does not match the
targets, and the worktree-cleanup step fails with
`fatal: pathspec '**/*.txt' did not match any files`.

The fix (matching upstream commit 1366c78c2) is to (a) parse the pathspecs with
PATHSPEC_PREFIX_ORIGIN so `.original` is populated, and (b) push
`ps.items[i].original` instead of `.match`, preserving the magic into the
child processes.

Run:  python3 fix_stash.py   (from anywhere; edits /app/src by default)
"""
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "/app/src"


def edit(path, old, new):
    with open(path) as f:
        s = f.read()
    if old not in s:
        sys.exit(f"ERROR: anchor not found in {path}:\n---\n{old}\n---")
    s = s.replace(old, new, 1)
    with open(path, "w") as f:
        f.write(s)


edit(
    f"{ROOT}/builtin/stash.c",
    "\t\targv_array_push(args, ps.items[i].match);",
    "\t\targv_array_push(args, ps.items[i].original);",
)
edit(
    f"{ROOT}/builtin/stash.c",
    "\tparse_pathspec(&ps, 0, PATHSPEC_PREFER_FULL, prefix, argv);",
    "\tparse_pathspec(&ps, 0, PATHSPEC_PREFER_FULL | PATHSPEC_PREFIX_ORIGIN,\n"
    "\t\t       prefix, argv);",
)
print("fix_stash.py: builtin/stash.c patched")
