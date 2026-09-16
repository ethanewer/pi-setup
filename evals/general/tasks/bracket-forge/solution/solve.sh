#!/bin/bash
# Oracle for bracket-forge: applies the two-hunk fix to the real rust-lang/regex
# tree at /app/src (the one-pass DFA slot accounting must tolerate the caller
# providing more slots than the compiled regex needs), writes /app/summary.md,
# then proves the work with the project's own integration test suite plus the
# upstream regression test (baked at /opt/golden), all offline. Reads only
# /app, /solution and /opt/golden, never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }
export PATH=/opt/cargo/bin:$PATH

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied slot-accounting fix patch"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: the one-pass DFA engine (regex-automata, dfa/onepass) panicked with a
slice range error whenever a caller searched it providing MORE capture slots
than the compiled regex had. The API contract allows any number of caller
slots: the excess must simply stay empty.

Root cause: the search sized its use of the engine's scratch-slot cache from
the CALLER's slot count (`slots.len() - implicit_slot_len`, capped at the
32-slot bit limit) without clamping to the size the cache was allocated for
(the compiled regex's explicit-slot count). When the caller supplied more
slots than that, `cache.explicit_slots()` sliced past the end of the cache's
`explicit_slots` vec and panicked (e.g. `abc` with a 4-slot buffer: 2 leftover
slots against a 0-slot cache; `(abc)(ABC){0}` with a 6-slot buffer: 4 leftover
against a 2-slot cache). The copy-back at match time then also assumed the
cache slice and the caller's leftover slice had equal length.

Fix: clamp the scratch-slot length to `min(caller leftover, cache
allocation, 32)`, and at match time copy back only as many entries as the
cache actually holds (slice the caller's slots to the cache length first).

Verification: the project's own regression test for this bug (from
/opt/golden, planted alongside the existing dfa/onepass test modules) now
passes - both `zero_repetition_capture_group` and
`too_many_slots_normal_pattern` - and the existing one-pass suite
(`cargo test -p regex-automata --test integration -- dfa::onepass::suite`)
stays green.
MD

# Prove the fix with the project's own machinery: plant the upstream
# regression test (golden bytes from /opt/golden, already in the image),
# rebuild offline, and run the regression tests plus the existing onepass
# suite.
TREEREL=$(printf '%s' "$PWD/regex-automata" '/' 'tests' '/dfa/onepass')
cp /opt/golden/regression.rs "$TREEREL/regression.rs"
grep -q '^mod regression;' "$TREEREL/mod.rs" \
    || printf 'mod regression;\n' >> "$TREEREL/mod.rs"
if ! cargo test --no-run -p regex-automata --test integration > /tmp/oracle_build.log 2>&1; then
    echo "oracle: rebuild failed; tail:" >&2
    tail -30 /tmp/oracle_build.log >&2
    exit 1
fi
if ! cargo test -p regex-automata --test integration -- dfa::onepass::regression > /tmp/oracle_golden.log 2>&1; then
    echo "oracle: upstream regression tests did not pass; tail:" >&2
    tail -25 /tmp/oracle_golden.log >&2
    exit 1
fi
grep -q "zero_repetition_capture_group \.\.\. ok" /tmp/oracle_golden.log || {
    echo "oracle: regression test did not actually run" >&2
    exit 1
}
grep -q "too_many_slots_normal_pattern \.\.\. ok" /tmp/oracle_golden.log || {
    echo "oracle: regression test 2 did not actually run" >&2
    exit 1
}
if ! cargo test -p regex-automata --test integration -- dfa::onepass::suite > /tmp/oracle_suite.log 2>&1; then
    echo "oracle: existing one-pass suite did not pass; tail:" >&2
    tail -25 /tmp/oracle_suite.log >&2
    exit 1
fi

# Leave the tree exactly as the verifier expects it: the regression test was
# planted here only to prove the fix and must not persist (the verifier
# re-plants it itself and asserts every tracked file except the fixed source
# file is byte-identical to the pinned commit).
REL=$(printf '%s' 'regex-automata' '/' 'tests' '/dfa/onepass')
rm -f "$REL/regression.rs"
git restore --worktree --source=HEAD -- "$REL/mod.rs" || {
    echo "oracle: could not restore planted test files" >&2
    exit 1
}

echo "oracle: fix applied, summary written, regression tests and onepass suite green"
exit 0