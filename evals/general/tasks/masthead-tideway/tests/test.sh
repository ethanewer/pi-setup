#!/bin/bash
# Verifier for masthead-tideway: proves the agent's fix in the real
# prometheus/prometheus tree at /app/src by (1) asserting the verifier's own
# trust anchors (the golden regression test, the pristine pre-fix source and
# the go toolchain still have the sha256 pinned at image build time), (2)
# asserting provenance (HEAD still the pinned parent commit; the upstream fix
# commit is not reachable from this clone; every tracked file except the
# single source file the bug lives in is byte-identical to the parent commit;
# no stray untracked files), (3) requiring /app/repro.sh and /app/summary.md,
# (4) discarding the compile cache so every executed binary is genuinely
# rebuilt from the tree's sources, (5) running the agent's own reproduction
# against the repaired tree (must pass) and against a scratch copy of the
# tree with the pristine pre-fix source restored (must fail - this proves the
# symptom is real and the reproduction targets it), (6) planting the upstream
# project's own regression test for this bug (compression_test.go extracted
# from the fix commit at image build time into /opt/golden, sha256-pinned)
# and running the whole httputil package suite, (7) running three authored
# hidden V tests that reach the same compression code path from inputs the
# upstream test does not use, each required to pass on the repaired tree and
# to fail on the pre-fix copy.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
LOG=/logs/verifier/verifier.log
: > "$LOG"

fail() {
    echo "FAIL: $1"
    echo "FAIL: $1" >> "$LOG"
    echo 0 > /logs/verifier/reward.txt
    exit 0
}

PARENT=1885dfd99d1b89d350ba4b56b3a74ffa0de50427
FIX=78169fb57d69371b24863b0f26555631a754204c
# Make every git read here immune to replace/graft refs: an adversarial agent
# can write refs/replace/<sha> (or set up grafts) to make `git rev-parse
# $PARENT:<path>` / `git ls-tree -r $PARENT` report a forged baseline. With
# replace objects disabled, git reads the true parent commit and its trees.
export GIT_NO_REPLACE_OBJECTS=1
export GOPATH=/opt/gopath XDG_CACHE_HOME=/opt/gocache
export PATH=/opt/go/bin:$PATH
GO=/opt/go/bin/go
PKG=util/httputil

cd /app/src || fail "/app/src is missing"

# 0) integrity anchors. An adversarial agent with write access to /opt (a
#    root trial) could otherwise replace the golden test with a lax copy,
#    replace the pristine pre-fix source with the agent's own fixed code (so
#    the pre-fix direction check fails to fail), or swap the go binary for a
#    stub that fakes a green run. The expected sha256 values are therefore
#    hardcoded HERE, in the verifier script itself (mounted read-only at
#    /tests), not just in /opt/pins: rewriting /opt is not enough to satisfy
#    them.
GOLDEN_SHA=ada8241e3ce7d9bac045604b81ddcafa66cc105efec90a964550134db5473382
PREFIX_SHA=58b85441fcaefdc3d538d7c938e2b98270809a9faf5413a056635b44f70e37ee
GOBIN_SHA=61e7455a40a2fdfcdab99e881cd30ba10e216e3d0f32ab5f8e59d10cac4ecf57
# sha256 of `git ls-tree -r $PARENT` over the TRUE parent tree (replace refs
# disabled), pinned here so the scope baseline itself cannot be forged via
# refs/replace or .git manipulation. Computed at image build time into
# /opt/pins/treelist.sha256 by the Dockerfile; this copy is the read-only
# anchor.
TREELIST_SHA=c952d70a1bcce6ffc0a27cd649d97a0c5c6d0f13980589fb6c2fcb392aa92ae3
have_golden=$(sha256sum /opt/golden/compression_test.go | awk '{print $1}')
have_prefix=$(sha256sum /opt/prefix/compression.go | awk '{print $1}')
have_gobin=$(sha256sum /opt/go/bin/go | awk '{print $1}')
if [ "$have_golden" != "$GOLDEN_SHA" ] || [ "$have_prefix" != "$PREFIX_SHA" ] || [ "$have_gobin" != "$GOBIN_SHA" ]; then
    fail "golden, pre-fix source or toolchain integrity check failed (substituted file: golden=$have_golden prefix=$have_prefix gobin=$have_gobin)"
fi
if ! "$GO" version >/dev/null 2>&1; then
    fail "go toolchain does not execute"
fi

# 1) provenance: the tree must still be at the pinned parent commit (no
#    commits added) and the upstream fix commit must not be reachable from
#    this object store (an agent that fetched or grafted the fix earns 0;
#    the fix direction must come from the agent's own work).
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi
if git cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "upstream fix commit is reachable from /app/src (fetch/graft detected)"
fi

# 2) scope: every change must live in exactly the one source file the bug
#    lives in. This is a CONTENT check, not a git-status check: the actual
#    bytes of every file on disk are hashed against the pinned commit's own
#    blobs, so assume-unchanged / skip-worktree tricks cannot hide a dirty
#    file. The baseline comes from `git ls-tree -r $PARENT` with replace refs
#    disabled and the full listing sha256-pinned, so the check does not
#    depend on the agent-writable .git/index, cannot be dodged by removing a
#    file from the index and hiding it via .git/info/exclude, and cannot be
#    re-pointed at a forged commit via refs/replace/grafts.
actual_treelist=$(git ls-tree -r "$PARENT" | sha256sum | awk '{print $1}')
if [ "$actual_treelist" != "$TREELIST_SHA" ]; then
    fail "parent tree listing hash mismatch (replace/graft refs or .git tampering): got $actual_treelist expected $TREELIST_SHA"
fi
have_treelist=$(awk '{print $1}' /opt/pins/treelist.sha256 2>/dev/null || true)
if [ -z "$have_treelist" ] || [ "$have_treelist" != "$TREELIST_SHA" ]; then
    fail "treelist pin in /opt/pins/treelist.sha256 does not match the verifier anchor (got $have_treelist expected $TREELIST_SHA)"
fi
ok=1
while IFS= read -r line; do
    meta=${line%%$'\t'*}
    path=${line#*$'\t'}
    read -r mode type sha <<< "$meta"
    case "$path" in
        util/httputil/compression.go) : ;;  # the one source file the bug lives in
        *)
            case "$type" in
                commit) : ;;  # gitlink/submodule: no worktree bytes to compare
                *)
                    if [ "$mode" = "120000" ]; then
                        have=$(printf '%s' "$(readlink "$path" 2>/dev/null)" | git hash-object --stdin 2>/dev/null || true)
                    else
                        have=$(git hash-object -- "$path" 2>/dev/null || true)
                    fi
                    if [ -z "$have" ] || [ "$have" != "$sha" ]; then
                        echo "worktree differs from parent for: $path" >> "$LOG"; ok=0
                    fi
                    ;;
            esac
            ;;
    esac
done < <(git ls-tree -r "$PARENT")
# Untracked files are refused, but only per-directory .gitignore rules may
# hide a file (the repository's own .gitignore line 29 covers go.work.sum,
# which `go test` writes); the agent-writable .git/info/exclude is NOT
# honoured, so a scratch/planted file cannot be hidden that way either.
while IFS= read -r -d '' f; do
    echo "untracked non-ignored file: $f" >> "$LOG"; ok=0
done < <(git ls-files --others -z --exclude-per-directory=.gitignore)
if [ "$ok" != "1" ]; then
    tail -30 "$LOG"
    fail "working tree modified outside the bug's source file (see $LOG)"
fi

# 3) deliverables: the agent's own failing reproduction and change summary.
[ -s /app/repro.sh ] || fail "/app/repro.sh is missing or empty"
[ -x /app/repro.sh ] || fail "/app/repro.sh is not executable"
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 4) discard the compile cache so everything executed below is genuinely
#    rebuilt from the tree as delivered; anything the agent planted under the
#    tool caches to fake a green run cannot survive, and a tree that does not
#    compile fails here.
rm -rf "${XDG_CACHE_HOME}/go-build"
mkdir -p "${XDG_CACHE_HOME}"

# 5) pre-fix scratch copy: the agent's tree with the pristine parent version
#    of the bug's source file restored (pinned bytes from /opt/prefix).
rm -rf /tmp/prefix
cp -a /app/src /tmp/prefix
cp /opt/prefix/compression.go /tmp/prefix/util/httputil/compression.go
want=$(git rev-parse "$PARENT:util/httputil/compression.go")
have=$(git -C /tmp/prefix hash-object /tmp/prefix/util/httputil/compression.go)
if [ "$have" != "$want" ]; then
    fail "pre-fix restoration failed: hash $have != parent blob $want"
fi

# 6) the agent's reproduction, both directions. Against the repaired tree it
#    must pass; against the pre-fix copy it must fail - any exit 0 there
#    means the reproduction is fake/hardcoded or the symptom is not what we
#    think it is.
if ! bash /app/repro.sh /app/src > /tmp/repro_fixed.out 2>&1; then
    echo "agent repro failed on the repaired tree; stdout:" >> "$LOG"
    head -10 /tmp/repro_fixed.out >> "$LOG"
    fail "agent repro exited nonzero on the repaired tree (see $LOG)"
fi
if bash /app/repro.sh /tmp/prefix > /tmp/repro_prefix.out 2>&1; then
    echo "agent repro passed against the PRE-FIX tree (expected failure); stdout:" >> "$LOG"
    head -10 /tmp/repro_prefix.out >> "$LOG"
    fail "agent repro did not fail on the pre-fix tree (see $LOG)"
fi

# 7) plant the upstream regression test (golden bytes, extracted from the fix
#    commit at image build time and sha256-pinned; never part of this task
#    tree) over the tree's copy of compression_test.go, then run the whole
#    httputil package suite.
cp /opt/golden/compression_test.go util/httputil/compression_test.go \
    || fail "cannot plant golden compression_test.go"
if ! ( cd /app/src && go test -v ./util/httputil > "$LOG.golden" 2>&1 ); then
    tail -30 "$LOG.golden" >&2
    fail "httputil package suite (with upstream regression test) did not pass (see $LOG.golden)"
fi
GOLDEN_SUBTESTS=$(grep -c -- "--- PASS: TestCompressionHandler_ContentLength/" "$LOG.golden")
if [ "$GOLDEN_SUBTESTS" -ne 12 ]; then
    tail -30 "$LOG.golden" >&2
    fail "upstream regression test: expected 12 passing subtests, saw $GOLDEN_SUBTESTS (see $LOG.golden)"
fi
for existing in TestCompressionHandler_PlainText TestCompressionHandler_Gzip TestCompressionHandler_Deflate TestCORSHandler; do
    grep -qF -- "--- PASS: $existing (" "$LOG.golden" || {
        tail -20 "$LOG.golden" >&2
        fail "$existing did not pass with the repaired tree (see $LOG.golden)"
    }
done

# 8) three authored hidden V tests: multi-write gzip with an explicit status,
#    short deflate body broken across writes with an explicit status, and an
#    empty deflate body with an explicit status line - inputs the upstream
#    regression test does not use. Each must PASS on the repaired tree and
#    FAIL on the pre-fix copy.
CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    gofile=$(ls "$case"/*_test.go 2>/dev/null | head -1)
    [ -n "$gofile" ] || fail "hidden case $name: no *_test.go file found"
    tname=$(grep -m1 -oE '^func [A-Za-z0-9_]+' "$gofile" | awk '{print $2}')
    [ -n "$tname" ] || fail "hidden case $name: no test function found in $gofile"
    fname=$(basename "$gofile")

    cp "$gofile" "/app/src/util/httputil/$fname" || fail "hidden case $name: cannot plant into repaired tree"
    if ! ( cd /app/src && go test -v ./util/httputil -run "$tname" > "/tmp/hc-$name-fixed.log" 2>&1 ) \
       || ! grep -qF -- "--- PASS: $tname (" "/tmp/hc-$name-fixed.log"; then
        tail -25 "/tmp/hc-$name-fixed.log" >&2
        fail "hidden case $name did not pass on the repaired tree (see log)"
    fi
    rm -f "/app/src/util/httputil/$fname"

    cp "$gofile" "/tmp/prefix/util/httputil/$fname"
    ( cd /tmp/prefix && go test -v ./util/httputil -run "$tname" > "/tmp/hc-$name-prefix.log" 2>&1 )
    rc=$?
    if ! grep -qF -- "--- FAIL: $tname (" "/tmp/hc-$name-prefix.log"; then
        echo "hidden case $name on the PRE-FIX copy: rc=$rc; log tail:" >> "$LOG"
        tail -15 "/tmp/hc-$name-prefix.log" >> "$LOG"
        fail "hidden case $name did not fail on the pre-fix copy (see $LOG)"
    fi
    rm -f "/tmp/prefix/util/httputil/$fname"
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 3 ] || fail "only $CASES hidden case(s) ran; expected 3"

echo "PASS: provenance, fix-unreachable, scope, deliverables, cache discard, repro both directions, golden httputil suite, and all hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0