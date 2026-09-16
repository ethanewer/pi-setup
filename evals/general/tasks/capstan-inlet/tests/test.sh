#!/bin/bash
# Verifier for capstan-inlet: proves the agent's fix in the real
# aquasecurity/trivy tree at /app/src by (1) asserting provenance (HEAD still
# the pinned parent commit, every tracked file except the single dotnet
# core_deps source file is byte-identical to it, no stray untracked files,
# and the object store holds nothing beyond the pinned commit), (2) requiring
# /app/summary.md, (3) planting the upstream project's own regression test for
# this bug (parse_test.go + the two fixtures as at the fix commit, extracted
# at image build time into /opt/golden) plus three authored hidden test
# modules, and (4) running the project's own Go test command on the core_deps
# package, demanding that it pass AND that every regression/hidden test
# function actually ran and passed (sabotaged or skipped tests leave no PASS
# line and therefore fail).
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

PARENT=f06520353fc632e69eaf9d669ecdd785e770305a
# The toolchain binary that speaks for the project's test results must be
# the exact bytes the Dockerfile downloaded from the pinned
# actions/go-versions release. The trial runs as root, so a wrapper could
# otherwise shadow or replace it and fake the whole test run on an
# unfixed tree.
GO_BIN_SHA=d68b7abbc40d0844f673f6cf06ae3cded225c50437c6454fa37ef178d079fe65
if [ "$(sha256sum /opt/go/bin/go | cut -d' ' -f1)" != "$GO_BIN_SHA" ]; then
    fail "/opt/go/bin/go is not the pinned toolchain binary (wrapper or tampering)"
fi
export PATH=/opt/go/bin:$PATH CGO_ENABLED=0 GOEXPERIMENT=jsonv2

cd /app/src || fail "/app/src is missing"

# 1) the tree must still be at the pinned parent commit (no commits added,
#    and nothing can hide work from the blob-level scope check below).
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi
if [ "$(git rev-list HEAD --count)" != "1" ]; then
    fail "clone contains history beyond the pinned parent commit"
fi

# 2) scope: every change must live in exactly the one source file the bug is
#    in (the .NET core_deps parser source, discovered by the agent, not named
#    here). We use git's own content comparison (status/diff), which is the
#    only comparison that understands the tree's .gitattributes eol rules and
#    tracked symlinks (some parent blobs are stored CRLF; a raw hash-object
#    byte comparison would false-positive on them and on symlinks). A
#    staging/assume-unchanged/skip-worktree trick cannot hide dirt:
#    `git diff --cached` must be empty (nothing staged), every tracked index
#    entry must be a fresh lowercase-free tag in `git ls-files -v` (no
#    assume-unchanged/skip-worktree), and `git status --porcelain` must report
#    exactly one change: the worktree modification of the single source file.
ok=1
if ! git diff --cached --quiet; then
    echo "staged changes present (index differs from HEAD)" >> "$LOG"; ok=0
fi
if git ls-files -v | grep -qE '^[^H]'; then
    echo "tracked entries with assume-unchanged/skip-worktree flags:"
    git ls-files -v | grep -E '^[^H]' >> "$LOG"; ok=0
fi
changes=$(git status --porcelain -- .)
if [ -n "$changes" ]; then
    only_parse=1
    while IFS= read -r line; do
        status_xy=${line:0:2}
        path=${line:3}
        case "$status_xy:$path" in
            " M:pkg/dependency/parser/dotnet/core_deps/parse.go") : ;;
            *) echo "out-of-scope change: [$status_xy] $path" >> "$LOG"; only_parse=0 ;;
        esac
    done <<EOF
$changes
EOF
    [ "$only_parse" = 1 ] || ok=0
fi
if [ "$ok" != "1" ]; then
    fail "working tree modified outside the bug's source file (see $LOG)"
fi

# 3) belt: the object store must hold nothing beyond the pinned parent commit
#    (no sneaked-in upstream commit, no hidden modifications).
unreachable=$(git fsck --no-reflogs --unreachable 2>/dev/null | wc -l)
if [ "$unreachable" != "0" ]; then
    fail "object store contains unreachable objects (see fsck)"
fi

# 4) deliverable: the agent's own change summary must exist.
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 5) plant the upstream regression test (golden bytes of core_deps
#    parse_test.go and its two fixtures from the fix commit, extracted at
#    image build time; never part of this task tree) and the three authored
#    hidden test modules into the core_deps package. The golden files are
#    baked into the image, so the trial user could in principle rewrite them
#    to neutralise the regression test; a pinned hash of the exact bytes
#    extracted from the fix commit catches any such tampering before the tree
#    is modified.
check_sha() { # file expected
    local have
    have=$(sha256sum "$1" | cut -d' ' -f1)
    [ "$have" = "$2" ] || fail "golden $1 was tampered with (sha256 $have, expected $2)"
}
check_sha /opt/golden/parse_test.go 0f16633e3526d2aada14ec6fb62b58282e5e91dde435e52d1be34d110cf8d005
check_sha /opt/golden/multi-project.deps.json 94f4a135e4d72dee418722bca9378f7a26e994d61ca3e3b64fe6c07fd6331e97
check_sha /opt/golden/ambiguous-root.deps.json 849abe17b54a5657773bd3cc0640b763f259d479ede15104124953b0c6df09c4

GOLD=pkg/dependency/parser/dotnet/core_deps
cp /opt/golden/parse_test.go "$GOLD/parse_test.go" || fail "cannot plant golden parse_test.go"
cp /opt/golden/multi-project.deps.json "$GOLD/testdata/multi-project.deps.json" || fail "cannot plant golden multi-project fixture"
cp /opt/golden/ambiguous-root.deps.json "$GOLD/testdata/ambiguous-root.deps.json" || fail "cannot plant golden ambiguous-root fixture"
cp /tests/hidden/workspace-rotate/zz_hidden_rotate_test.go "$GOLD/zz_hidden_rotate_test.go" || fail "cannot plant hidden case 1"
cp /tests/hidden/workspace-rotate/fixture.deps.json "$GOLD/testdata/hidden-rotate.deps.json" || fail "cannot plant hidden case 1 fixture"
cp /tests/hidden/no-root/zz_hidden_noroot_test.go "$GOLD/zz_hidden_noroot_test.go" || fail "cannot plant hidden case 2"
cp /tests/hidden/no-root/fixture.deps.json "$GOLD/testdata/hidden-noroot.deps.json" || fail "cannot plant hidden case 2 fixture"
cp /tests/hidden/diamond/zz_hidden_diamond_test.go "$GOLD/zz_hidden_diamond_test.go" || fail "cannot plant hidden case 3"
cp /tests/hidden/diamond/fixture.deps.json "$GOLD/testdata/hidden-diamond.deps.json" || fail "cannot plant hidden case 3 fixture"

# 6) run the project's own Go test command on the core_deps package: the
#    planted golden regression test plus the hidden cases must ALL pass.
go test -v -short ./pkg/dependency/parser/dotnet/core_deps/ > /logs/verifier/gotest.log 2>&1
rc=$?
if [ $rc -ne 0 ]; then
    echo "go test exit=$rc" >> "$LOG"
    tail -40 /logs/verifier/gotest.log >> "$LOG"
    fail "the project's own core_deps test command failed (exit $rc; see $LOG)"
fi

# 7) belt: every required test must actually have RUN and PASSED (a
#    neutralised or skipped run would leave no PASS line even with exit 0).
for t in \
    TestParse/multi-project_solution \
    TestParse/ambiguous_root \
    TestParse/happy_path \
    TestHiddenRotate \
    TestHiddenNoRoot \
    TestHiddenDiamond; do
    if ! grep -q -- "--- PASS: ${t} " /logs/verifier/gotest.log; then
        fail "required test ${t} did not RUN and PASS in the core_deps suite (see gotest.log)"
    fi
done

echo 1 > /logs/verifier/reward.txt
echo "VERIFIER: all checks passed, reward=1"
exit 0