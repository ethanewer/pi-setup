#!/bin/bash
# Verifier for chainplate-hull: proves the agent's fix in the real
# starship/starship tree at /app/src by (1) asserting provenance (HEAD still
# the pinned parent commit; every tracked file except the single formatter
# source file is byte-identical to it; no stray untracked files; the fix
# commit is not reachable), (2) requiring /app/summary.md, (3) rebuilding the
# debug `starship` binary and the project's own test harness offline, (4)
# planting the upstream project's own regression tests for this bug
# (three inline unit tests extracted from the fix commit at image build time
# into /opt/golden) into the formatter source file and running them, (5)
# running a targeted selection of the project's own existing formatter unit
# tests, and (6) running four authored hidden CLI cases that reach the same
# empty-textgroup/prev_fg-prev_bg code path from format strings the upstream
# tests do not use.
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

PARENT=0dd5a4f402c8d94524aaaa5632b2d0cba7fe1630
FIX=91861886a779805cd8265a85c629e579d513aa75
export PATH=/opt/cargo/bin:$PATH

cd /app/src || fail "/app/src is missing"

# 1) the tree must still be at the pinned parent commit: no commits added,
#    and nothing can hide work from the blob-level scope check below. The
#    upstream fix commit (which an agent must not be able to look up or
#    fetch) must not be reachable.
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi
if git cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "fix commit ${FIX} is reachable from /app/src"
fi

# 2) scope: every change must live in exactly the one formatter source file
#    the bug is in (discovered by the agent, not named here). This is a
#    CONTENT check, not a git-status check: we hash the actual bytes of
#    every tracked file on disk against the pinned commit's own blob, so
#    assume-unchanged/skip-worktree tricks cannot hide a dirty file, and we
#    refuse any untracked non-ignored file.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        src/formatter/string_formatter.rs) : ;;
        *)
            want=$(git rev-parse "$PARENT:$f" 2>/dev/null || true)
            if [ -z "$want" ]; then
                echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
            fi
            # Symlinked tracked files must be hashed by their link target,
            # not by following the link.
            if [ -L "$f" ]; then
                have=$(printf '%s' "$(readlink "$f")" | git hash-object --stdin 2>/dev/null || true)
            else
                have=$(git hash-object -- "$f" 2>/dev/null || true)
            fi
            if [ -z "$have" ] || [ "$have" != "$want" ]; then
                echo "out-of-scope modified/deleted tracked file: $f" >> "$LOG"; ok=0
            fi
            ;;
    esac
done < <(git ls-files -z)
while IFS= read -r -d '' f; do
    echo "untracked non-ignored file: $f" >> "$LOG"; ok=0
done < <(git ls-files --others -z --exclude-standard)
if [ "$ok" != "1" ]; then
    tail -30 "$LOG"
    fail "working tree modified outside the bug's source file (see $LOG)"
fi

# 3) deliverable: the agent's own change summary must exist.
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 4) rebuild the debug `starship` from the agent's tree (proves the tree
#    compiles), then plant the upstream regression tests (golden bytes,
#    extracted from the fix commit at image build time as the complete
#    inline `mod tests` block; never part of this task tree) into the
#    formatter source file, and rebuild the test harness offline.
if ! cargo build --locked > "$LOG.build" 2>&1; then
    tail -40 "$LOG.build" >&2
    fail "cargo build failed on the agent's tree (see $LOG.build)"
fi
test -x /app/src/target/debug/starship || fail "no starship debug binary after build"
python3 /app/plant_golden.py /app/src/src/formatter/string_formatter.rs \
    /opt/golden/string_formatter_tests.rs || fail "could not plant golden tests"
grep -q "test_empty_textgroup_propagates_prev_bg" \
    /app/src/src/formatter/string_formatter.rs || fail "planted golden tests missing"
if ! cargo test --no-run --locked > "$LOG.build2" 2>&1; then
    tail -40 "$LOG.build2" >&2
    fail "cargo test --no-run failed after planting regression tests (see $LOG.build2)"
fi

# 5) the upstream regression tests must pass. (On the unfixed tree these
#    tests fail: the empty textgroup produces zero segments, so
#    test_empty_textgroup_with_style asserts 0 == 1, and the propagation test
#    fails to find a previous style.)
GOLDEN="test_empty_textgroup_with_style test_empty_textgroup_without_style test_empty_textgroup_propagates_prev_bg"
if ! cargo test --locked -- $GOLDEN > /tmp/golden.out 2>&1; then
    tail -40 /tmp/golden.out >&2
    fail "upstream regression tests for this bug did not pass (see /tmp/golden.out)"
fi
for t in $GOLDEN; do
    grep -q "$t \.\.\. ok" /tmp/golden.out || {
        fail "golden test $t did not actually run and pass (see /tmp/golden.out)"
    }
done

# 6) a targeted selection of the project's OWN existing formatter unit tests
#    covering the same machinery (textgroups, styles, variables, nesting,
#    shell escaping) must stay green. Every required test must actually have
#    run and passed (a neutralised run would leave no "<name> ... ok" line
#    even though the binary exited 0).
EXISTING="test_default_style test_nested_textgroup test_styled_variable_as_text test_style_variable_nested test_meta_variable test_conditional test_nested_conditional test_bash_escape"
if ! cargo test --locked -- $EXISTING > /tmp/existing.out 2>&1; then
    tail -40 /tmp/existing.out >&2
    fail "project's existing formatter tests failed (see /tmp/existing.out)"
fi
for t in $EXISTING; do
    if ! grep -q "$t \.\.\. ok" /tmp/existing.out; then
        fail "existing test ${t} did not run and pass (see /tmp/existing.out)"
    fi
done

# 7) four authored hidden CLI cases: other format strings reaching the same
#    empty-textgroup/prev_fg-prev_bg path. Each must print the byte-exact
#    expected rendering and exit 0. (Three of them print a bare text byte
#    with no escapes on the unfixed tree; the fourth guards the pre-existing
#    non-empty-group behaviour.)
#
#    The fifth hidden case is GENERATED HERE at verify time: a random hex
#    background color chosen from a fresh random seed, with the expected
#    bytes computed by formula (never by running the binary). Because the
#    input string is produced inside the verifier, no static enumeration of
#    inputs - neither the upstream tests nor any hidden-case fixture - can
#    anticipate it; only a fix that makes the empty textgroup mechanism
#    general (any color, any color space) survives.
CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    work=/tmp/hc-$name
    rm -rf "$work"; mkdir -p "$work"
    cp "$case"input "$work"/input 2>/dev/null || fail "hidden case $name: missing input"
    cp "$case"expected "$work"/expected || fail "hidden case $name: missing expected"
    cp "$case"run.sh "$work"/run.sh || fail "hidden case $name: missing run.sh"
    ( cd "$work" && bash run.sh > stdout.txt 2> stderr.txt )
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "hidden case $name: starship exited $rc (expected 0); stderr:" >> "$LOG"
        head -8 "$work/stderr.txt" >> "$LOG"
        fail "hidden case $name: starship exited $rc (see $LOG)"
    fi
    if ! cmp -s "$work/stdout.txt" "$work/expected"; then
        echo "hidden case $name: stdout mismatch; got:" >> "$LOG"
        od -An -c "$work/stdout.txt" | head -10 >> "$LOG"
        fail "hidden case $name: output mismatch (see $LOG)"
    fi
    CASES=$((CASES + 1))
done

# 7b) generated hidden case: random hex color, expected bytes by formula.
work=/tmp/hc-generated
rm -rf "$work"; mkdir -p "$work"
r1=$((RANDOM % 256)); r2=$((RANDOM % 256)); r3=$((RANDOM % 256))
hex=$(printf "%02x%02x%02x" "$r1" "$r2" "$r3")
printf 'format = "[](bg:#%s)[X](bg:prev_bg)"\nadd_newline = false\n' "$hex" > "$work/input"
printf '\033[48;2;%d;%d;%dmX\033[0m' "$r1" "$r2" "$r3" > "$work/expected"
cat > "$work/run.sh" <<'RUN'
#!/bin/bash
# Generated hidden case (see /tests/test.sh): random hex colour on the
# empty-textgroup / prev_bg code path. Output is byte-compared by
# /tests/test.sh against the formula-computed `expected`.
export STARSHIP_CONFIG="$PWD/input"
exec /app/src/target/debug/starship prompt
RUN
( cd "$work" && bash run.sh > stdout.txt 2> stderr.txt )
rc=$?
if [ "$rc" -ne 0 ]; then
    echo "hidden case generated: starship exited $rc (expected 0); stderr:" >> "$LOG"
    head -8 "$work/stderr.txt" >> "$LOG"
    fail "hidden case generated: starship exited $rc (see $LOG)"
fi
if ! cmp -s "$work/stdout.txt" "$work/expected"; then
    echo "hidden case generated (bg:#$hex): stdout mismatch; got:" >> "$LOG"
    od -An -c "$work/stdout.txt" | head -10 >> "$LOG"
    fail "hidden case generated: output mismatch (see $LOG)"
fi
CASES=$((CASES + 1))
[ "$CASES" -ge 5 ] || fail "only $CASES hidden case(s) ran; expected 5"

echo "PASS: provenance, /app/summary.md, build, upstream regression tests, existing suite, and all hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0