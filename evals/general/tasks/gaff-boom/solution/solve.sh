#!/bin/bash
# Oracle for gaff-boom: fixes the real explosion/spaCy tree at /app/src for the
# memory-zone exception-cleanup bug (issue #13924), writes the two deliverables
# /app/repro.py and /app/summary.md, recompiles the changed Cython extension
# modules, and proves the work with the project's own machinery: the agent's
# own reproduction, the upstream regression test planted at /opt/golden, and a
# slice of the project's existing vocab_vectors suite. Reads only /app,
# /solution and /opt/golden, never the verifier's own files.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

# Apply the fix: wrap the `yield mem` of both memory_zone context managers in
# try/finally so transient-string cleanup and memory-pool restore always run,
# even when an exception propagates through the context manager.
git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied memory-zone try/finally fix"

# Deliverable: the agent's reproduction (real, fails on the pre-fix code).
cat > /app/repro.py <<'PY'
#!/usr/bin/env python3
"""Reproduction for the spaCy memory-zone exception-cleanup bug.

Behaviour on a buggy checkout: entering a memory zone, raising inside the
zone, and catching the exception leaves the vocabulary stuck in memory-zone
state (in_memory_zone still True) with the transient word leaked and the
vocabulary still writing to the temporary memory pool. Exits nonzero on that
broken state; exits 0 once the cleanup runs on the exception path.
"""
from spacy.vocab import Vocab

vocab = Vocab()
_ = vocab["dog"]
assert "dog" in vocab

try:
    with vocab.memory_zone():
        _ = vocab["horse"]
        raise ValueError("simulated error")
except ValueError:
    pass

if vocab.in_memory_zone:
    print("DIAGNOSIS: vocab stuck in memory-zone state after an exception")
    raise SystemExit(1)
if "horse" in vocab:
    print("DIAGNOSIS: transient word from failed memory zone leaked")
    raise SystemExit(1)
lex = vocab["cat"]
assert lex.text == "cat"
print("REPRO-OK: memory zone cleaned up correctly after an exception")
PY
chmod +x /app/repro.py

# Deliverable: the write-up.
cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: spaCy 3.8's memory-zone context managers restored normal vocabulary
behaviour only when the `with` block exited normally. Both `Vocab.memory_zone`
and `StringStore.memory_zone` are generator-based context managers that `yield`
the memory pool and then, on the way out, clear the transient strings and
restore the non-transient memory pool. When an exception propagates out of the
`with` block, the generator frame is closed at the `yield` and every statement
after it is skipped, so the cleanup never ran: the vocab stayed in
memory-zone state, the transient words were never freed, and all subsequent
vocabulary operations kept using the temporary pool.

Fix: wrap the `yield` in each `memory_zone` context manager in `try/finally`
so the transient-string cleanup and the memory-pool restore always run, no
matter how the block exits. Normal-exit behaviour is unchanged.

Verification: the project's own regression test for this bug
(`test_memory_zone_exception_cleanup`, planted from /opt/golden) passes, the
agent's own reproduction fails before the fix and passes after it, and the
existing vocab_vectors suite slice stays green.
MD

# Recompile the two changed extension modules (touch + remove the stale .so
# so cythonize always regenerates them from the patched sources).
rm -f spacy/strings.cpython-312-x86_64-linux-gnu.so spacy/vocab.cpython-312-x86_64-linux-gnu.so
touch spacy/strings.pyx spacy/vocab.pyx
python3 setup.py build_ext --inplace > /tmp/oracle_build.log 2>&1 || {
    echo "oracle: rebuild failed; tail:" >&2
    tail -20 /tmp/oracle_build.log >&2
    exit 1
}
test -f spacy/strings.cpython-312-x86_64-linux-gnu.so || { echo "oracle: strings .so missing" >&2; exit 1; }
test -f spacy/vocab.cpython-312-x86_64-linux-gnu.so || { echo "oracle: vocab .so missing" >&2; exit 1; }

# Prove it with the project's own machinery: the agent-facing reproduction,
# the upstream regression test, and a slice of the existing suite, all offline.
if ! python3 /app/repro.py > /tmp/oracle_repro.log 2>&1; then
    echo "oracle: reproduction did not pass after the fix; tail:" >&2
    tail -10 /tmp/oracle_repro.log >&2
    exit 1
fi

cd spacy
cd tests/vocab_vectors
cp /opt/golden/test_memory_zone.py test_memory_zone.py
if ! python3 -m pytest test_memory_zone.py -q -p no:cacheprovider > /tmp/oracle_golden.log 2>&1; then
    echo "oracle: upstream regression test did not pass; tail:" >&2
    tail -20 /tmp/oracle_golden.log >&2
    exit 1
fi
grep -q "4 passed" /tmp/oracle_golden.log || {
    echo "oracle: golden test count wrong; tail:" >&2
    tail -5 /tmp/oracle_golden.log >&2
    exit 1
}

if ! python3 -m pytest test_stringstore.py test_vocab_api.py test_lexeme.py test_lookups.py \
        -q -p no:cacheprovider > /tmp/oracle_suite.log 2>&1; then
    echo "oracle: existing suite slice did not pass; tail:" >&2
    tail -20 /tmp/oracle_suite.log >&2
    exit 1
fi
cd /app/src/spacy
# Leave the tree exactly as the verifier expects it: the golden test was
# planted here only to prove the fix and must not persist (the verifier
# re-plants it itself and asserts every tracked file except the fixed source
# files equals the pinned commit).
git restore --worktree --source=HEAD -- tests/vocab_vectors/test_memory_zone.py || {
    echo "oracle: could not restore the test file" >&2
    exit 1
}

echo "oracle: fix applied, deliverables written, rebuild green, golden + suite green"
exit 0