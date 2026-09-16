#!/bin/bash
# Verifier for gaff-boom: proves the agent's fix in the real explosion/spaCy
# tree at /app/src for the memory-zone exception-cleanup bug by
# (1) asserting the verifier's own trust anchors (sha256 pins of the golden
#     regression test and of git, recorded at image build time),
# (2) asserting provenance (HEAD still the pinned parent commit; every tracked
#     file except the two allowed sources is byte-identical to it; the two
#     allowed sources actually differ; no untracked files),
# (3) requiring the deliverables /app/repro.py and /app/summary.md,
# (4) forcing a fresh recompile of the two changed extension modules from the
#     agent's sources (stale or planted .so binaries are deleted first), and
#     running a runtime probe that proves the compiled binaries really carry
#     the fix,
# (5) running the agent's own /app/repro.py against the repaired tree — it
#     must pass — and, after reverting the two sources to the pinned parent
#     and recompiling, against the PRE-FIX tree — it must FAIL with a
#     memory-zone diagnosis, proving the reproduction is genuine,
# (6) planting the project's own regression test for this bug (extracted from
#     the fix commit at image build time into /opt/golden, sha256-pinned) and
#     running it plus a slice of the project's existing vocab_vectors suite,
#     and
# (7) running three authored hidden cases that reach the same exception path
#     from inputs the upstream test does not use.
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

PARENT=453732d32d55029ea9787ef737c8cf8d626f45b0
export PYTHONPATH=/app/src
export PYTHONDONTWRITEBYTECODE=1
GIT=/usr/bin/git

cd /app/src || fail "/app/src is missing"

# 0) trust anchors: the golden regression test bytes and the git binary must
#    still be the ones recorded at image build time (an adversarial agent with
#    write access to /opt could otherwise swap either).
if ! ( cd / && sha256sum -c /opt/pins/golden.sha256 >/dev/null 2>&1 ) || \
   ! ( cd / && sha256sum -c /opt/pins/git.sha256 >/dev/null 2>&1 ); then
    fail "integrity pins check failed (substituted golden test or git binary)"
fi

# 0b) the installed library must be the tree at /app/src, not a planted copy.
if ! python3 -c 'import spacy; assert spacy.__file__.startswith("/app/src/"), spacy.__file__' > /tmp/spacy_import.log 2>&1; then
    fail "import spacy does not resolve to /app/src: $(head -1 /tmp/spacy_import.log)"
fi

# 1) the tree must still be at the pinned parent commit.
if [ "$("$GIT" rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $("$GIT" rev-parse HEAD), expected pinned $PARENT"
fi

# 2) scope: content-hash every tracked file against the pinned parent blob;
#    only the two allowed sources may differ, and both must differ.
if ! python3 /tests/scope_check.py > /tmp/scope.log 2>&1; then
    cat /tmp/scope.log >> "$LOG" 2>/dev/null
    fail "tree scope check failed: $(tail -1 /tmp/scope.log)"
fi

# 3) deliverables present and non-trivial.
[ -x /app/repro.py ] || fail "/app/repro.py missing or not executable"
[ -s /app/summary.md ] || fail "/app/summary.md missing or empty"
grep -qiE "memory.?zone|memory_zone" /app/summary.md || fail "/app/summary.md does not discuss the memory zone"
grep -qiE "exception" /app/summary.md || fail "/app/summary.md does not discuss the exception path"

# Save the agent's actual change for the pre-fix reversion dance below.
"$GIT" diff -- spacy/strings.pyx spacy/vocab.pyx > /tmp/agent.diff
[ -s /tmp/agent.diff ] || fail "no modification in the allowed sources"
# (the re-apply at step 6 runs `git apply` against the reverted clean tree,
#  so any malformed diff surfaces there.)

# Deterministic rebuild of the two changed extension modules: delete stale
# compiled artifacts and force fresh mtimes so Cython regenerates and gcc
# recompiles them from the CURRENT sources on disk.
rebuild() {
    rm -f spacy/strings.cpython-312-x86_64-linux-gnu.so \
          spacy/vocab.cpython-312-x86_64-linux-gnu.so
    find build -type f \( -name 'strings.c' -o -name 'strings.o' \
        -o -name 'vocab.c' -o -name 'vocab.o' \) -delete 2>/dev/null
    touch spacy/strings.pyx spacy/vocab.pyx
    python3 setup.py build_ext --inplace > /tmp/rebuild.log 2>&1 || {
        echo "FAIL: rebuild failed; tail:" >> "$LOG"
        tail -20 /tmp/rebuild.log >> "$LOG" 2>/dev/null
        return 1
    }
    [ -f spacy/strings.cpython-312-x86_64-linux-gnu.so ] || return 1
    [ -f spacy/vocab.cpython-312-x86_64-linux-gnu.so ] || return 1
    return 0
}

# 4) repaired tree: rebuild from the agent's sources, probe the runtime, and
#    run the agent's own reproduction — it must pass.
rebuild || fail "rebuild from agent sources failed"
if ! python3 /tests/probe_fixed.py > /tmp/probe_fixed.log 2>&1; then
    fail "fixed-direction probe failed (rebuild did not take effect): $(tail -2 /tmp/probe_fixed.log)"
fi
if ! python3 /app/repro.py > /tmp/repro_fixed.log 2>&1; then
    fail "agent /app/repro.py did not pass on the repaired tree: $(tail -2 /tmp/repro_fixed.log)"
fi

# 5) PRE-FIX tree: revert the two sources to the pinned parent, rebuild, prove
#    the bug is genuinely present again, then run the agent's reproduction —
#    it must FAIL, and the failure must be the memory-zone symptom.
"$GIT" checkout -- spacy/strings.pyx spacy/vocab.pyx || fail "could not revert sources"
rebuild || fail "rebuild of reverted tree failed"
if ! python3 /tests/probe_parent.py > /tmp/probe_parent.log 2>&1; then
    fail "parent-direction probe failed (revert ineffective): $(tail -2 /tmp/probe_parent.log)"
fi
if python3 /app/repro.py > /tmp/repro_parent.log 2>&1; then
    fail "agent /app/repro.py did not fail on the pre-fix tree (vacuous reproduction?)"
fi
grep -qiE "memory.?zone|memory_zone|in_memory_zone|transient" /tmp/repro_parent.log \
    || fail "pre-fix reproduction failure did not diagnose the memory-zone symptom: $(tail -2 /tmp/repro_parent.log)"

# 6) restore the agent's fix, rebuild, and run the project's own machinery:
#    the upstream regression test for this bug plus a slice of the existing
#    vocab_vectors suite, all offline.
"$GIT" apply /tmp/agent.diff > /dev/null 2>&1 || fail "could not re-apply the agent diff"
rebuild || fail "rebuild after re-applying the agent diff failed"
if ! python3 /tests/probe_fixed.py > /tmp/probe_fixed2.log 2>&1; then
    fail "fixed-direction probe after re-apply failed (rebuild did not take effect)"
fi
if ! python3 /app/repro.py > /tmp/repro_fixed2.log 2>&1; then
    fail "agent /app/repro.py did not pass after re-apply"
fi

cp /opt/golden/test_memory_zone.py spacy/tests/vocab_vectors/test_memory_zone.py
if ! python3 -m pytest spacy/tests/vocab_vectors/test_memory_zone.py -q -p no:cacheprovider > /tmp/golden.log 2>&1; then
    tail -20 /tmp/golden.log >> "$LOG" 2>/dev/null
    fail "upstream golden regression test did not pass"
fi
grep -q "4 passed" /tmp/golden.log || fail "golden run did not report 4 passed ($(tail -1 /tmp/golden.log))"

if ! python3 -m pytest \
        spacy/tests/vocab_vectors/test_stringstore.py \
        spacy/tests/vocab_vectors/test_vocab_api.py \
        spacy/tests/vocab_vectors/test_lexeme.py \
        spacy/tests/vocab_vectors/test_lookups.py \
        -q -p no:cacheprovider > /tmp/suite.log 2>&1; then
    tail -20 /tmp/suite.log >> "$LOG" 2>/dev/null
    fail "existing suite slice did not pass"
fi
grep -qE "passed" /tmp/suite.log || fail "suite slice reported no passing tests"
"$GIT" restore --worktree --source=HEAD -- spacy/tests/vocab_vectors/test_memory_zone.py || true

# 7) authored hidden cases on the same exception-cleanup path.
for d in /tests/hidden/*/; do
    case_script="${d}case.py"
    [ -f "$case_script" ] || fail "hidden case script missing: $case_script"
    if ! python3 "$case_script" > /tmp/hidden_case.log 2>&1; then
        fail "hidden case $(basename "$d") failed: $(tail -3 /tmp/hidden_case.log | tr '\n' ' ')"
    fi
done

echo "VERIFIER-OK: scope, deliverables, both-direction repro, golden regression, suite slice and hidden cases all green"
echo 1 > /logs/verifier/reward.txt
exit 0