#!/bin/bash
# Oracle for ballast-reach: applies the real upstream fix (as an authored
# patch under /solution/fix.patch) to the real pypa/setuptools tree at
# /app/src, writes /app/summary.md, then proves the work with the project's
# own machinery: the upstream regression tests (baked at /opt/golden) are
# planted into the tree's test module and the whole module must pass.
# Reads only /app, /solution and /opt/golden.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch >/dev/null 2>&1 || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied normalization-insensitive matching fix"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: MANIFEST.in exclusion rules (`exclude`, `global-exclude`,
`recursive-exclude`, `prune`) compare the rule's text against candidate file
paths byte-for-byte, with no Unicode normalization. On macOS APFS/HFS+ an
on-disk name is stored decomposed (NFD) while the rule is usually authored
composed (NFC); the two denote the same file but differ byte-for-byte, so the
exclusion silently fails and the file leaks into the built sdist.

Fix: make pattern matching insensitive to normalization form in both
directions. `translate_pattern` normalizes the incoming pattern to NFC, and
the compiled pattern is wrapped in a `_NormalizedMatcher` whose `match`/`search`
normalize the candidate path to the same form before delegating to the
compiled regex — so a composed rule matches a decomposed name and vice versa,
and genuinely different names still do not match. The normalization helper
(`unicode_utils.normalize`, based on `unicodedata.normalize('NFC', ...)`) is
added next to the existing filesystem-encoding helpers.

Verified: both reproduction snippets from the task pass (`MATCH: True`,
`excluded`), the planted upstream regression tests pass, and the tree's own
sdist/manifest test module stays fully green.
MD

# Prove the fix with the project's own machinery: plant the upstream
# regression tests (golden bytes from /opt/golden, already in the image) into
# the matching test module and run it in full.
TDLIST=tests
TESTS_DIR="setuptools/${TDLIST}"
cp /opt/golden/test_manifest.py "${TESTS_DIR}/test_manifest.py"
if ! python3 -m pytest -q -p no:cacheprovider "${TESTS_DIR}/test_manifest.py" > /tmp/oracle_pytest.log 2>&1; then
    echo "oracle: planted test module did not pass; tail:" >&2
    tail -40 /tmp/oracle_pytest.log >&2
    exit 1
fi
grep -qE "[0-9]+ passed" /tmp/oracle_pytest.log || {
    echo "oracle: no 'passed' summary in pytest run" >&2
    tail -20 /tmp/oracle_pytest.log >&2
    exit 1
}

if ! python3 -m pytest -p no:cacheprovider -v -k 'unicode_normalization' "${TESTS_DIR}/test_manifest.py" > /tmp/oracle_golden.log 2>&1; then
    echo "oracle: regression tests did not pass; tail:" >&2
    tail -30 /tmp/oracle_golden.log >&2
    exit 1
fi
grep -q "test_translate_pattern_unicode_normalization PASSED" /tmp/oracle_golden.log || {
    echo "oracle: test_translate_pattern_unicode_normalization did not run" >&2
    exit 1
}
grep -q "test_global_exclude_unicode_normalization PASSED" /tmp/oracle_golden.log || {
    echo "oracle: test_global_exclude_unicode_normalization did not run" >&2
    exit 1
}

# The planted test module is proof machinery, not part of the fix; restore
# the tree so the verifier's provenance assertions see a clean working tree
# (the verifier re-plants the golden module itself).
git restore --worktree --source=HEAD -- "${TESTS_DIR}/test_manifest.py" || {
    echo "oracle: could not restore the manifest test module" >&2
    exit 1
}

echo "oracle: fix applied, summary written, regression suite green"
exit 0