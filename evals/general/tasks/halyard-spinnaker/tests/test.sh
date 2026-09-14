#!/bin/bash
# Verifier for halyard-spinnaker: proves the agent's fix in the real
# gohugoio/hugo tree at /app/src by (1) asserting the verifier's own trust
# anchors (go binary, git, the golden regression test and the pre-fix hugo
# binary still have the sha256 pinned at image build time), (2) asserting
# provenance (HEAD is still the pinned parent commit, the upstream fix
# commit is not reachable in the clone, every tracked file except the two
# source files the bug lives in is byte-identical to the parent commit, and
# there are no stray untracked files), (3) requiring /app/repro.sh and
# /app/summary.md, (4) forcing a fresh hugo CLI build offline from the
# agent's tree into a fresh path (an agent-planted binary cannot survive),
# (5) running the agent's own reproduction against the repaired binary
# (must pass) and against a pristine pre-fix binary baked at
# /opt/prefix/hugo (must fail - this proves the symptom is real and the
# reproduction targets it), (6) planting the project's own regression test
# (extracted from the fix commit at image build time into /opt/golden,
# sha256-pinned) and running it, (7) running nine of the project's own
# partial/template hugolib tests (they must not just exit 0 - each named
# test must actually run and pass), and (8) running four authored hidden
# cases that reach the same broken code path from falsy inputs the upstream
# test does not use.
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

PARENT=8ee6de6d96a64395d27416d4f2ad7d172a2686d0
FIX=5758c370eac6c4460cd6bb34d4475c8d347585f6
export PATH=/usr/local/go/bin:$PATH
GIT=/usr/bin/git
GO=/usr/local/go/bin/go

cd /app/src || fail "/app/src is missing"

# 0) integrity anchors. The verifier executes the tree, the harness, the
#    golden test and the pre-fix binary; an adversarial agent with write
#    access to /opt could otherwise swap the go binary for a stub that
#    reports success for every build, replace /opt/prefix/hugo with a fixed
#    binary (so the pre-fix direction check fails to fail), or tamper with
#    the golden test, and earn reward 1 on an untouched tree. The pins
#    recorded at image build time detect any substitution before anything
#    is executed.
if ! ( cd / && sha256sum -c /opt/pins/anchors.sha256 >/dev/null 2>&1 ); then
    fail "trust-anchor integrity check failed (substituted file)"
fi

# 1) provenance: the tree must still be at the pinned parent commit (no
#    commits added), and the upstream fix commit must not be reachable in
#    this clone (the agent is expected to find the fix itself).
if [ "$("$GIT" rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $("$GIT" rev-parse HEAD), expected pinned $PARENT"
fi
if "$GIT" cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "upstream fix commit ${FIX} is reachable in the clone"
fi

# 2) scope: every change must live in exactly the two source files the bug
#    lives in (discovered by the agent, not named here). This is a CONTENT
#    check, not a git-status check: we hash the actual bytes of every
#    tracked file on disk against the pinned commit's own blob, so
#    assume-unchanged / skip-worktree tricks cannot hide a dirty file, and
#    we refuse any untracked non-ignored file.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        tpl/partials/partials.go|tpl/tplimpl/template_ast_transformers.go) : ;;
        *)
            want=$("$GIT" rev-parse "$PARENT:$f" 2>/dev/null || true)
            if [ -z "$want" ]; then
                echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
            fi
            if [ -L "$f" ]; then
                have=$(printf '%s' "$(readlink "$f")" | "$GIT" hash-object --stdin 2>/dev/null || true)
            else
                have=$("$GIT" hash-object -- "$f" 2>/dev/null || true)
            fi
            if [ -z "$have" ] || [ "$have" != "$want" ]; then
                echo "out-of-scope modified/deleted tracked file: $f" >> "$LOG"; ok=0
            fi
            ;;
    esac
done < <("$GIT" ls-files -z)
while IFS= read -r -d '' f; do
    echo "untracked non-ignored file: $f" >> "$LOG"; ok=0
done < <("$GIT" ls-files --others -z --exclude-standard)
if [ "$ok" != "1" ]; then
    tail -30 "$LOG"
    fail "working tree modified outside the bug's source files (see $LOG)"
fi

# 3) deliverables: the agent's own failing reproduction and change summary.
[ -s /app/repro.sh ] || fail "/app/repro.sh is missing or empty"
[ -x /app/repro.sh ] || fail "/app/repro.sh is not executable"
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 4) rebuild the hugo CLI from the agent's tree into a fresh path (proves
#    the tree compiles). Any binary the agent may have planted is ignored;
#    everything below runs the verifier's own build.
rm -f /tmp/hugo-rebuilt /app/hugo
if ! "$GO" build -o /tmp/hugo-rebuilt > "$LOG.build" 2>&1; then
    tail -40 "$LOG.build" >&2
    fail "go build failed on the agent's tree (see $LOG.build)"
fi
[ -x /tmp/hugo-rebuilt ] || fail "go build produced no hugo binary"
if [ "$(od -An -tx1 -N4 /tmp/hugo-rebuilt | tr -d ' \n')" != "7f454c46" ]; then
    fail "rebuilt binary is not a real ELF executable"
fi
if ! /tmp/hugo-rebuilt version 2>/dev/null | grep -q "hugo v0.91.0-DEV"; then
    fail "rebuilt binary is not the hugo CLI from this tree"
fi

# 5) the agent's reproduction, both directions. Against the repaired binary
#    it must pass - exit 0 AND the rendered page must be printed. Against
#    the pristine pre-fix binary baked into the image it must fail with
#    output - any exit 0 there means the reproduction is fake/hardcoded or
#    does not target the symptom.
if ! HUGO_BIN=/tmp/hugo-rebuilt bash /app/repro.sh > /tmp/repro_fixed.out 2>&1; then
    echo "agent repro failed on the repaired tree; stdout:" >> "$LOG"
    head -10 /tmp/repro_fixed.out >> "$LOG"
    fail "agent repro exited nonzero on the repaired tree (see $LOG)"
fi
if [ ! -s /tmp/repro_fixed.out ]; then
    fail "agent repro printed no rendered page on the repaired tree"
fi
if HUGO_BIN=/opt/prefix/hugo bash /app/repro.sh > /tmp/repro_prefix.out 2>&1; then
    echo "agent repro PASSED against the PRE-FIX binary (expected failure); stdout:" >> "$LOG"
    head -10 /tmp/repro_prefix.out >> "$LOG"
    fail "agent repro did not fail on the pre-fix tree (see $LOG)"
fi
if [ ! -s /tmp/repro_prefix.out ]; then
    echo "agent repro printed nothing on the pre-fix tree;" >> "$LOG"
    fail "agent repro printed no output on the pre-fix tree (see $LOG)"
fi

# 6) plant the upstream regression test (golden bytes, extracted from the
#    fix commit at image build time and sha256-pinned; never part of this
#    task tree) into the tree, then run it with the project's own test
#    runner. On the unfixed tree this test fails with the 'needs a
#    non-zero argument' build error.
rm -f hugolib/template_test.go
cp /opt/golden/template_test.go hugolib/template_test.go || fail "cannot plant golden regression test"
if ! "$GO" test -vet=off ./hugolib -run TestPartialWithZeroedArgs -v > "$LOG.golden" 2>&1; then
    tail -30 "$LOG.golden" >&2
    fail "upstream regression test for this bug did not pass (see $LOG.golden)"
fi
grep -q "^--- PASS: TestPartialWithZeroedArgs " "$LOG.golden" || {
    tail -30 "$LOG.golden" >&2
    fail "TestPartialWithZeroedArgs did not actually run and pass (see $LOG.golden)"
}

# 7) nine of the project's own existing partial/template tests must stay
#    green, and each must ACTUALLY have run and passed (a neutralised run
#    would not print the per-test PASS lines even though the binary exits
#    NOT print the per-test PASS lines even though the binary exits 0).
SUITE_REGEX="TestPartialWithReturn|TestPartialCached|TestPartialInline|TestPartialInlineBase|TestTemplateTruth|TestTemplateFuncs|TestTemplateLookupOrder|TestTemplateManyBaseTemplates|TestTemplateNoBasePlease"
if ! "$GO" test -vet=off ./hugolib -run "$SUITE_REGEX" -v > "$LOG.suite" 2>&1; then
    tail -30 "$LOG.suite" >&2
    fail "project's existing partial/template tests failed (see $LOG.suite)"
fi
for t in TestPartialWithReturn TestPartialCached TestPartialInline TestPartialInlineBase \
         TestTemplateTruth TestTemplateFuncs TestTemplateLookupOrder \
         TestTemplateManyBaseTemplates TestTemplateNoBasePlease; do
    if ! grep -q "^--- PASS: $t " "$LOG.suite"; then
        fail "existing test ${t} did not run and pass (see $LOG.suite)"
    fi
done

# 8) four authored hidden cases: falsy arguments the upstream test does not
#    use - an empty string from front matter, an empty list from a data
#    file, false computed by an expression, and a falsy value returned by
#    another partial - each must build with exit 0 and render the
#    byte-exact expected page.
CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    work=/tmp/hc-$name
    rm -rf "$work"; mkdir -p "$work"
    cp "$case"run.sh "$work"/run.sh || fail "hidden case $name: missing run.sh"
    cp "$case"expected "$work"/expected || fail "hidden case $name: missing expected"
    ( cd "$work" && HUGO_BIN=/tmp/hugo-rebuilt bash run.sh > stdout.txt 2> stderr.txt )
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "hidden case $name: hugo exited $rc (expected 0); stderr:" >> "$LOG"
        head -8 "$work/stderr.txt" >> "$LOG"
        fail "hidden case $name: hugo exited $rc (see $LOG)"
    fi
    if ! cmp -s "$work/stdout.txt" "$work/expected"; then
        echo "hidden case $name: stdout mismatch; got:" >> "$LOG"
        od -c "$work/stdout.txt" | head -8 >> "$LOG"
        fail "hidden case $name: output mismatch (see $LOG)"
    fi
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 4 ] || fail "only $CASES hidden case(s) ran; expected 4"

echo "PASS: provenance, deliverables, build, repro both directions, upstream regression test, existing suite, and all hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0