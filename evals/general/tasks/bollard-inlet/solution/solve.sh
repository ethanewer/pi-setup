#!/bin/bash
# Oracle for bollard-inlet: applies the canonical upstream fix for the
# symlinked-.stignore bug to /app/src, writes the deliverables, and proves
# the task is passable by running the reproduction against the fixed tree.
set -u

cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

# 1) apply the upstream fix (parent -> fix, 5 source files).
if ! git apply --whitespace=nowarn /solution/upstream-fix.patch; then
    echo "oracle: git apply failed" >&2
    exit 1
fi

# 2) deliverables.
cp /solution/repro.sh /app/repro.sh
chmod +x /app/repro.sh

cat > /app/summary.md <<'EOF'
# summary: ignore rules silently not applied when .stignore is a symlink

## Root cause

Opening files through the project's filesystem abstraction always adds the
`O_NOFOLLOW` open flag ("never open symlinks as the final path component"),
which is the right default for scanning folders. But the ignore-file loader
uses that same open path for the folder's `.stignore`, so a `.stignore` that
is itself a symlink to the real rules file can no longer be opened at all:
the OS refuses the final symlink component and the folder scan logs
`open .../.stignore: too many levels of symbolic links`. The scanner treats
that as "no ignore file present" and continues, so the configured ignore
patterns are silently not applied and excluded files get scanned and synced.

## Fix

Added an explicit `OptFollow` open flag to the filesystem abstraction and
honoured it in the open path: the flag clears the default no-follow
behaviour for exactly the call sites that opt in. The ignore-file loader now
opens `.stignore` with that flag, so a symlinked `.stignore` resolves to the
real rules file and its patterns load and apply as they did before the
no-follow tightening. All other open sites keep the default no-follow
semantics.

Verified with the reproduction in `/app/repro.sh` plus the project's own
regression test (`TestIgnoreThroughSymlink`), the full `lib/ignore` and
`lib/fs` test suites, and the hidden generalization cases -- all pass on the
fixed tree, and the reproduction fails with the reported diagnostic on the
unfixed tree.
EOF

# 3) prove the task is passable: the reproduction must pass on the fixed
#    tree (this also leaves the build cache warm for the verifier).
if ! bash /app/repro.sh /app/src; then
    echo "oracle: reproduction failed on the fixed tree" >&2
    exit 1
fi

echo "oracle OK"
exit 0