#!/bin/bash
# Verifier for yaw-roadstead.
#
# Proves the agent fixed the real spf13/cobra bug in /app/src (YAML
# see_also entries for nested subcommands must carry the full command path)
# by running:
#   1) integrity anchors: /opt/pins sha256 for the golden regression test
#      and the toolchain binaries (detect substitution before trusting
#      anything);
#   2) provenance: /app/src still at the pinned parent commit, fix commit
#      unreachable, exactly one commit;
#   3) the deliverable /app/repro.sh must exist and be executable;
#   4) the agent's OWN reproduction must exit 0 on the repaired /app/src;
#   5) the same reproduction must exit non-zero on a pristine copy of the
#      tree (tracked files reverted to the parent bytes, the agent's added
#      files left in place) - the "pre-fix tree concept";
#   6) the same reproduction must exit 0 on a copy of the pristine tree to
#      which only the upstream one-line fix is applied - proves the repro
#      tracks tree content rather than path/argument cheats;
#   7) the project's own upstream regression test for this bug (extracted
#      from the fix commit at image build time into /opt/golden, sha256
#      pinned, never part of this task tree) is overlaid onto the repaired
#      tree and must pass (-run TestGenYamlDoc);
#   8) the project's WHOLE existing suite must stay green on the repaired
#      tree (proves the fix broke nothing else);
#   9) two authored hidden cases (Go tests building their own command
#      trees with names the upstream test never uses) must pass on the
#      repaired tree AND fail on the pristine parent tree, so passing the
#      golden test alone is insufficient.
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

PARENT=6bf8cd85825800c5cbc63009b1fb2c54185f05ed
FIX=7790bf97fd40e285913066cf65387ad281cd6c2e
export PATH=/opt/go/bin:$PATH
GIT=/usr/bin/git

# --- 1) integrity anchors -----------------------------------------------------
if ! ( cd / && sha256sum -c /opt/pins/golden.sha256 >/dev/null 2>&1 ) || \
   ! ( cd / && sha256sum -c /opt/pins/toolchain.sha256 >/dev/null 2>&1 ); then
    fail "toolchain or golden integrity check failed (substituted binary or test)"
fi

# --- 2) provenance ------------------------------------------------------------
cd /app/src || fail "/app/src is missing"
[ "$("$GIT" rev-parse HEAD)" = "$PARENT" ] || fail "HEAD is $("$GIT" rev-parse HEAD), expected pinned $PARENT"
[ "$("$GIT" rev-list --all --count)" = "1" ] || fail "object store holds more than the parent commit"
if "$GIT" cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "fix commit is reachable from /app/src"
fi
[ -f doc/yaml_docs.go ] || fail "doc/yaml_docs.go missing"

# --- 3) deliverable -----------------------------------------------------------
[ -f /app/repro.sh ] || fail "/app/repro.sh is missing"
[ -x /app/repro.sh ] || fail "/app/repro.sh is not executable"

# --- 4) the agent's reproduction on the REPAIRED tree -------------------------
if ! ( cd /app/src && /app/repro.sh > /tmp/repro-src.log 2>&1 ); then
    echo "repro on repaired tree failed; tail of output:" >> "$LOG"
    tail -8 /tmp/repro-src.log >> "$LOG"
    fail "agent's reproduction (/app/repro.sh) did not pass on the repaired tree (see $LOG)"
fi

# --- snapshots ----------------------------------------------------------------
rm -rf /tmp/deliver /tmp/prefix /tmp/prefix-fixed
cp -a /app/src /tmp/deliver || fail "cannot snapshot /app/src"
cp -a /app/src /tmp/prefix
cp -a /app/src /tmp/prefix-fixed

# --- 5) the agent's reproduction on the PRE-FIX tree concept ------------------
# Revert every tracked file to the parent bytes; the agent's untracked
# files (the repro's dependencies) remain, so the repro can still compile
# and must then hit the real bug.
( cd /tmp/prefix && "$GIT" checkout -- . ) || fail "cannot reset pre-fix copy"
PRE_RC=0
if ( cd /tmp/prefix && /app/repro.sh > /tmp/repro-prefix.log 2>&1 ); then
    PRE_RC=1
    echo "repro output on the pre-fix tree (unexpectedly passing):" >> "$LOG"
    tail -8 /tmp/repro-prefix.log >> "$LOG"
    fail "agent's reproduction passed on the PRE-FIX tree; it does not reproduce the bug (see $LOG)"
fi
[ "$PRE_RC" = 0 ] || fail "pre-fix reproduction check errored unexpectedly"

# --- 6) repro must ALSO pass when only the upstream fix is applied ------------
# Rules out path/argument/pwd-based cheats: the same script must track tree
# content, passing exactly when the see_also output is corrected.
( cd /tmp/prefix-fixed && "$GIT" checkout -- . )
( cd /tmp/prefix-fixed && sed -i 's/child.Name()+" - "+child.Short/child.CommandPath()+" - "+child.Short/' doc/yaml_docs.go )
if ! ( cd /tmp/prefix-fixed && /app/repro.sh > /tmp/repro-fixed.log 2>&1 ); then
    echo "repro output on upstream-fix-only tree:" >> "$LOG"
    tail -8 /tmp/repro-fixed.log >> "$LOG"
    fail "agent's reproduction failed on a tree with only the upstream fix applied (see $LOG)"
fi

# --- 7) the upstream golden regression test on the repaired tree --------------
# First, revert the tracked test-support file that defines the assertion
# helpers (checkStringContains/checkStringOmits) AND the fixture commands
# (rootCmd/echoCmd/echoSubCmd/emptyRun) to the pristine parent bytes. The
# golden, full-suite and hidden-case checks below must run against those
# REAL helpers, not whatever the agent left in the working tree; otherwise an
# agent could neutralize checkStringContains/checkStringOmits in
# doc/cmd_test.go and pass every substantive check with the see_also bug
# still in place (proven: the pre-fix tree + no-op helpers scored 1). The
# source fix in doc/yaml_docs.go is intentionally left as the agent left it,
# so the checks still exercise the agent's actual fix.
if ! ( cd /tmp/deliver && "$GIT" checkout -- doc/cmd_test.go ); then
    fail "cannot restore pristine doc/cmd_test.go in deliver snapshot"
fi
# belt: the restored helper must really assert (the Errorf form that a no-op
# neutralization removes).
if ! grep -q 't.Errorf("Expected to contain' /tmp/deliver/doc/cmd_test.go; then
    fail "doc/cmd_test.go does not contain a real assertion helper (was it neutralized?)"
fi
# The golden regression test (fixed doc/yaml_docs_test.go from the fix commit) is
# overlaid in the snapshot; whatever the agent did to test files is
# irrelevant.
cp /opt/golden/yaml_docs_test.go /tmp/deliver/doc/yaml_docs_test.go || fail "cannot overlay golden test"
if ! ( cd /tmp/deliver && go test -v ./... -run TestGenYamlDoc > /tmp/golden.log 2>&1 ); then
    tail -12 /tmp/golden.log >> "$LOG"
    fail "upstream golden regression test did not pass on the repaired tree (see $LOG)"
fi
grep -q "^--- PASS: TestGenYamlDoc " /tmp/golden.log || fail "golden regression test did not actually run and pass"
grep -q "^--- PASS: TestGenYamlDocRunnable " /tmp/golden.log || fail "golden run did not include TestGenYamlDocRunnable"

# --- 8) the project's whole existing suite stays green ------------------------
if ! ( cd /tmp/deliver && go test -v ./... > /tmp/full.log 2>&1 ); then
    tail -12 /tmp/full.log >> "$LOG"
    fail "full upstream test suite failed on the repaired tree (see $LOG)"
fi

# --- 9) hidden cases ----------------------------------------------------------
# Each authored hidden case must PASS on the repaired tree and FAIL on the
# pre-fix tree. They build their own command trees (three-level nesting;
# sibling subtrees) with names the upstream test never uses, so neither
# editing cmd_test.go nor special-casing the upstream names can pass them.
HCASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    src=""
    src=$(find "$case" -maxdepth 1 -name '*.go' | head -1)
    [ -n "$src" ] || { echo "hidden case $name: missing .go file" >> "$LOG"; fail "hidden case $name has no test source"; }
    func=$(basename "$src" .go)
    cp "$src" /tmp/deliver/doc/"$name"_test.go || fail "hidden case $name: cannot stage test file"
    if ! ( cd /tmp/deliver && go test -v ./... -run "$func" > "/tmp/hc-$name-deliver.log" 2>&1 ); then
        echo "hidden case $name (repaired tree):" >> "$LOG"
        tail -10 "/tmp/hc-$name-deliver.log" >> "$LOG"
        fail "hidden case $name failed on the repaired tree (see $LOG)"
    fi
    grep -q "^--- PASS: $func " "/tmp/hc-$name-deliver.log" || fail "hidden case $name did not actually run and pass"
    cp "$src" /tmp/prefix/doc/"$name"_test.go || fail "hidden case $name: cannot stage test file on pre-fix tree"
    if ( cd /tmp/prefix && go test -v ./... -run "$func" > "/tmp/hc-$name-prefix.log" 2>&1 ); then
        echo "hidden case $name PASSED on the pre-fix tree (must fail):" >> "$LOG"
        tail -6 "/tmp/hc-$name-prefix.log" >> "$LOG"
        fail "hidden case $name passed on the PRE-FIX tree; it does not bite the bug (see $LOG)"
    fi
    HCASES=$((HCASES + 1))
done
[ "$HCASES" -ge 2 ] || fail "only $HCASES hidden case(s) exercised; expected at least 2"

rm -rf /tmp/deliver /tmp/prefix /tmp/prefix-fixed

echo "PASS: provenance, /app/repro.sh (src pass, pre-fix fail, upstream-fix pass), golden regression test, full suite, and $HCASES hidden cases both directions"
echo 1 > /logs/verifier/reward.txt
exit 0