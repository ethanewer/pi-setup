#!/bin/bash
# Oracle for ballast-fathom: repair builtin/stash.c in the real upstream tree,
# write the diagnosis deliverable, rebuild with the project's own make, and
# self-check the fix with a direct repro. No verifier-path references here.
set -u
cd /app/src || { echo "no /app/src"; exit 1; }

python3 /solution/fix_stash.py || { echo "fix_stash.py failed"; exit 1; }

mkdir -p /app
cat > /app/diagnosis.md <<'EOF'
# Root cause: git stash -u drops glob-magic pathspec prefixes

The built-in `git stash` parses its pathspecs in `push_stash()` with
`parse_pathspec(&ps, 0, PATHSPEC_PREFER_FULL, prefix, argv)`. Because the
`PATHSPEC_PREFIX_ORIGIN` flag is not set, each pathspec that survives parsing has
an empty `.original` field, and `add_pathspecs()` pushes `ps.items[i].match` into
the argv of the internal `git add` / `git diff-index` / `git ls-files` child
processes. `.match` is the *parsed* form, from which magic prefixes such as
`:(glob)` have been stripped.

So `git stash -u -- ':(glob)**/*.txt'` hands the child the bare pattern
`**/*.txt`. Without the glob magic, git's ordinary pathspec matching does not
treat that as the recursive wildcard the user asked for, so the worktree-cleanup
step of the stash fails with `fatal: pathspec '**/*.txt' did not match any
files`, the command exits non-zero, and the untracked files are left in the
working tree even though the stash was saved.

The fix is two lines in `builtin/stash.c`: parse the pathspecs with the
`PATHSPEC_PREFIX_ORIGIN` flag so the original (pre-parse) form is retained, and
push `ps.items[i].original` instead of `ps.items[i].match` in `add_pathspecs()`.
That keeps the `:(glob)` magic intact as the pathspec travels into the internal
commands, so they match the intended files and the untracked files are correctly
stashed and removed from the worktree.
EOF

if ! make -j1 > /tmp/oracle_build.log 2>&1; then
  echo "oracle: build failed:" >&2
  tail -20 /tmp/oracle_build.log >&2
  exit 1
fi
[ -x /app/src/git ] || { echo "oracle: no /app/src/git produced"; exit 1; }

# direct self-check of the fix
export GIT_EXEC_PATH=/app/src
R=/tmp/oracle-repro
rm -rf "$R" && mkdir -p "$R" && cd "$R" || exit 1
/app/src/git init -q .
/app/src/git config user.email oracle@localhost
/app/src/git config user.name oracle
echo tracked > tracked.txt
/app/src/git add tracked.txt
/app/src/git commit -qm init >/dev/null
echo untracked > untracked.txt
if ! /app/src/git stash -u -- ':(glob)**/*.txt' > /tmp/oracle_repro.log 2>&1; then
  echo "oracle: repro still fails after fix:"; cat /tmp/oracle_repro.log
  exit 1
fi
if [ -e untracked.txt ]; then echo "oracle: untracked.txt not stashed"; exit 1; fi
/app/src/git stash pop -q || { echo "oracle: pop failed"; exit 1; }
[ "$(cat untracked.txt)" = untracked ] || { echo "oracle: pop did not restore"; exit 1; }

echo "oracle: fix applied, built, and repro passes (stash -u glob -> exit 0, file removed, pop restores)"
