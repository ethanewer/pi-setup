#!/bin/bash
# Verifier for capstan-deepwater: proves the agent's fix in the real
# BurntSushi/ripgrep tree at /app/src. The bug (upstream issue #2990): the
# globset file-name extractor drops the final path component whenever a path
# ends in a dot, so globs whose final component ends in a dot silently stop
# matching (a negation glob excludes nothing, an inclusion glob selects
# nothing). The verifier
#   1. asserts provenance: HEAD is still the pinned parent commit, every
#      tracked file except crates/globset/src/pathutil.rs is byte-identical
#      to its parent blob (content check, immune to assume-unchanged tricks),
#      there are no untracked non-ignored files, and /app/summary.md exists
#      and is non-empty;
#   2. rebuilds the debug `rg` binary and, after planting the upstream
#      regression test (golden bytes from /opt/golden, extracted from the
#      fix commit at image build time, never part of this task tree),
#      rebuilds the project's own test harness offline;
#   3. runs the project's OWN regression test r2990_trip_over_trailing_dot
#      through the project's own test runner (must pass);
#   4. runs a targeted selection of the project's own existing glob
#      integration tests (must all run and pass);
#   5. runs hidden CLI cases that fail on the unfixed tree and pass on the
#      fixed one: four static cases (a negated literal glob on a file named
#      'mubla.', an included literal glob selecting 'mubla.', a '**/'-prefixed
#      negation over a nested trailing-dot directory 'nxq.', and a search-mode
#      run over a tree containing a trailing-dot directory 'grxv.') plus four
#      DYNAMIC cases whose trailing-dot NAME is generated at verifier time
#      from $RANDOM, so no fixed name can ever be hardcoded (the name does
#      not exist anywhere until the verifier itself creates it; even an agent
#      that could read /tests would find no name to special-case).
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

PARENT=ba23ced8178496263af013117b70c09ce39c18e5
FIX=4df1298127695ed1e76937f16de1a0135677ccf5
GOLDEN_SHA=48708bd6aa3534e703a11b101de09a66794206ffc043be966abba3cfde07801e
SRCFILE=crates/globset/src/pathutil.rs
export PATH=/opt/cargo/bin:$PATH

cd /app/src || fail "/app/src is missing"

# 1) the tree must still be at the pinned parent commit.
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi

# 2) the upstream fix commit must not be reachable (an agent that fetched and
#    applied it would have it in the object store).
if git cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "the upstream fix commit is reachable from the working clone"
fi

# 3) scope: every change must live in exactly the one source file the bug is
#    in (crates/globset/src/pathutil.rs, discovered by the agent, not named
#    in the instruction). CONTENT check: hash the actual bytes of every
#    tracked file on disk against the pinned commit's own blob, and refuse
#    any untracked non-ignored file.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        crates/globset/src/pathutil.rs) : ;;
        *)
            want=$(git rev-parse "$PARENT:$f" 2>/dev/null || true)
            if [ -z "$want" ]; then
                echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
            fi
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
if [ -z "$(git diff -- "$SRCFILE" 2>/dev/null || true)" ]; then
    fail "the deliverable /app/src is unchanged (no fix was implemented)"
fi

# 4) deliverable: the agent's own change summary must exist.
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 5) rebuild the debug `rg` from the agent's tree (proves the tree compiles)
#    and plant the upstream regression test (golden bytes, extracted from
#    the fix commit at image build time; never part of this task tree) into
#    the test harness, then rebuild the harness offline.
if ! cargo build > "$LOG.build" 2>&1; then
    tail -40 "$LOG.build" >&2
    fail "cargo build failed on the agent's tree (see $LOG.build)"
fi
cp /opt/golden/regression.rs tests/regression.rs || fail "cannot plant golden regression test"
if [ "$(sha256sum tests/regression.rs | cut -d' ' -f1)" != "$GOLDEN_SHA" ]; then
    fail "golden regression test bytes do not match the pinned upstream file"
fi
if ! cargo test --no-run > "$LOG.build2" 2>&1; then
    tail -40 "$LOG.build2" >&2
    fail "cargo test --no-run failed after planting regression test (see $LOG.build2)"
fi

# 6) locate the project's own integration test binary (new cargo layout puts
#    test executables under target/debug/deps/).
BIN=""
for b in $(ls -t target/debug/deps/integration-* 2>/dev/null); do
    case "$b" in *.d) continue ;; esac
    BIN=$b; break
done
[ -n "$BIN" ] && [ -x "$BIN" ] || fail "project integration test binary not found"

# 7) the upstream regression test must pass. (On the unfixed tree this test
#    fails: rg lists both asdf./foo and asdf/foo where only asdf/foo is
#    expected.)
if ! "$BIN" --test-threads 1 r2990_trip_over_trailing_dot > /tmp/golden.out 2>&1; then
    tail -30 /tmp/golden.out >&2
    fail "upstream regression test for this bug did not pass (see /tmp/golden.out)"
fi
grep -q "regression::r2990_trip_over_trailing_dot \.\.\. ok" /tmp/golden.out || {
    fail "regression::r2990_trip_over_trailing_dot did not actually run and pass (see /tmp/golden.out)"
}

# 8) a targeted selection of the project's OWN existing integration tests
#    covering the same machinery (glob selection, negation, case
#    insensitivity, includes) must stay green, and every required test must
#    actually have run and passed.
EXISTING="misc::glob misc::glob_negate misc::glob_case_insensitive misc::glob_case_sensitive misc::glob_always_case_insensitive misc::include_zero misc::include_zero_override misc::preprocessing_glob"
if ! "$BIN" --test-threads 1 $EXISTING > /tmp/existing.out 2>&1; then
    tail -30 /tmp/existing.out >&2
    fail "project's existing glob tests failed (see /tmp/existing.out)"
fi
for t in $EXISTING; do
    if ! grep -q "$t \.\.\. ok" /tmp/existing.out; then
        fail "existing test ${t} did not run and pass (see /tmp/existing.out)"
    fi
done

# 9a) four static authored hidden CLI cases: other inputs reaching the same
#     broken path. Each must print the byte-exact expected output and exit 0.
#     Every case fails on the unfixed tree (negation glob silently ignored,
#     or inclusion glob silently matching nothing). The run scripts always
#     pass an explicit path argument so rg's stdin heuristic never comes into
#     play. The fixture names (mubla., nxq., grxv.) appear in no agent-visible
#     artifact: not in the instruction, the README, the Dockerfile, the
#     solution or /opt/golden.
CASES=0
for case in /tests/hidden/*/; do
    [ -d "$case" ] || continue
    name=$(basename "$case")
    work=/tmp/hc-$name
    rm -rf "$work"; mkdir -p "$work"
    cp "$case"run.sh "$work"/run.sh || fail "hidden case $name: missing run.sh"
    cp "$case"expected "$work"/expected || fail "hidden case $name: missing expected"
    ( cd "$work" && bash run.sh > stdout.txt 2> stderr.txt )
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "hidden case $name: rg exited $rc (expected 0); stderr:" >> "$LOG"
        head -8 "$work/stderr.txt" >> "$LOG"
        fail "hidden case $name: rg exited $rc (see $LOG)"
    fi
    if ! cmp -s "$work/stdout.txt" "$work/expected"; then
        echo "hidden case $name: stdout mismatch; got:" >> "$LOG"
        od -c "$work/stdout.txt" | head -8 >> "$LOG"
        fail "hidden case $name: output mismatch (see $LOG)"
    fi
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 4 ] || fail "only $CASES static hidden case(s) ran; expected 4"

# 9b) four DYNAMIC hidden cases: same broken path, but the trailing-dot NAME
#     is generated here from $RANDOM at verifier time. The verifier builds the
#     fixture, runs rg against it, and compares to an expectation it computes
#     from its own fixture knowledge (LC_ALL=C sort reproduces rg's
#     --sort=path byte ordering). An agent that hardcodes any set of names
#     fails these cases, because the name it would have to hardcode is not
#     created until after the agent is gone. All four shapes fail on the
#     unfixed tree for the same reason as the static cases.
RN=$(printf '%s' "$RANDOM$RANDOM$RANDOM" | cksum | cut -d' ' -f1)
RNAME=$(printf '%s' "$RN" | md5sum | cut -c1-8)   # hex [0-9a-f], glob-safe
DYNAS=0

dyn_fail() {  # $1 = case label, $2 = workdir, $3 = rc
    echo "dynamic case $1: failure (rc=$3); got:" >> "$LOG"
    [ -f "$2/stdout.txt" ] && od -c "$2/stdout.txt" | head -8 >> "$LOG"
    [ -f "$2/stderr.txt" ] && { echo "stderr:" >> "$LOG"; head -8 "$2/stderr.txt" >> "$LOG"; }
    fail "dynamic case $1: see $LOG"
}

# (1) negation of a trailing-dot FILE whose name is random
case1=/tmp/dyn-c1; rm -rf "$case1"; mkdir -p "$case1/fx"
: > "$case1/fx/plain1"; : > "$case1/fx/plain2"
: > "$case1/fx/$RNAME"; : > "$case1/fx/$RNAME."
( cd "$case1" && /app/src/target/debug/rg --sort=path --files -g "!$RNAME." fx > stdout.txt 2> stderr.txt )
rc=$?
[ "$rc" -ne 0 ] && dyn_fail dyn-neg-file "$case1" "$rc"
got1=$(cat "$case1/stdout.txt")
want1=$(printf 'fx/plain1\nfx/plain2\nfx/%s\n' "$RNAME" | LC_ALL=C sort)
[ "$got1" = "$want1" ] || {
    echo "dynamic case dyn-neg-file: got '$got1' want '$want1'" >> "$LOG"
    fail "dynamic case dyn-neg-file: output mismatch (see $LOG)"
}
DYNAS=$((DYNAS + 1))

# (2) inclusion of a trailing-dot FILE whose name is random
case2=/tmp/dyn-c2; rm -rf "$case2"; mkdir -p "$case2/fx"
: > "$case2/fx/plain1"; : > "$case2/fx/$RNAME."
( cd "$case2" && /app/src/target/debug/rg --sort=path --files -g "$RNAME." fx > stdout.txt 2> stderr.txt )
rc=$?
[ "$rc" -ne 0 ] && dyn_fail dyn-inc-file "$case2" "$rc"
got2=$(cat "$case2/stdout.txt")
[ "$got2" = "fx/$RNAME." ] || {
    echo "dynamic case dyn-inc-file: got '$got2' want 'fx/$RNAME.'" >> "$LOG"
    fail "dynamic case dyn-inc-file: output mismatch (see $LOG)"
}
DYNAS=$((DYNAS + 1))

# (3) '**/'-prefixed negation of a NESTED random-name trailing-dot directory
case3=/tmp/dyn-c3; rm -rf "$case3"; mkdir -p "$case3/fx/a/$RNAME." "$case3/fx/a/plain"
: > "$case3/fx/a/$RNAME./x"; : > "$case3/fx/a/$RNAME./x."
: > "$case3/fx/a/plain/x"
( cd "$case3" && /app/src/target/debug/rg --sort=path --files -g "!**/$RNAME./" fx > stdout.txt 2> stderr.txt )
rc=$?
[ "$rc" -ne 0 ] && dyn_fail dyn-neg-dir "$case3" "$rc"
got3=$(cat "$case3/stdout.txt")
[ "$got3" = "fx/a/plain/x" ] || {
    echo "dynamic case dyn-neg-dir: got '$got3' want 'fx/a/plain/x'" >> "$LOG"
    fail "dynamic case dyn-neg-dir: output mismatch (see $LOG)"
}
DYNAS=$((DYNAS + 1))

# (4) search mode with a negation glob for a random-name trailing-dot directory
case4=/tmp/dyn-c4; rm -rf "$case4"; mkdir -p "$case4/fx/$RNAME." "$case4/fx/plain"
printf 'secret\n' > "$case4/fx/$RNAME./foo"
printf 'secret\n' > "$case4/fx/plain/foo"
( cd "$case4" && /app/src/target/debug/rg --sort=path -g "!$RNAME./" secret fx > stdout.txt 2> stderr.txt )
rc=$?
[ "$rc" -ne 0 ] && dyn_fail dyn-search "$case4" "$rc"
got4=$(cat "$case4/stdout.txt")
[ "$got4" = "fx/plain/foo:secret" ] || {
    echo "dynamic case dyn-search: got '$got4' want 'fx/plain/foo:secret'" >> "$LOG"
    fail "dynamic case dyn-search: output mismatch (see $LOG)"
}
DYNAS=$((DYNAS + 1))

[ "$DYNAS" -eq 4 ] || fail "only $DYNAS/4 dynamic hidden case(s) ran"

echo "PASS: dynamic hidden cases ran with random name $RNAME" >> "$LOG"

echo "PASS: provenance, /app/summary.md, build, upstream regression test, existing suite, and all hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0