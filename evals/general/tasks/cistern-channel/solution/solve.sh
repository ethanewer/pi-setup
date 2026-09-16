#!/bin/bash
# Oracle for cistern-channel: applies the fix to the real falconry/falcon
# tree at /app/src (each MultipartParseOptions must start from its own copy
# of the default media handlers instead of a shared class-level Handlers
# instance), writes /app/summary.md, then proves the work with the project's
# own pytest suite plus the upstream regression test (baked at /opt/golden),
# all offline. Reads only /app, /solution and /opt/golden, never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied handler-isolation fix patch"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: every `MultipartParseOptions` instance initialised its `media_handlers`
attribute by aliasing the same class-level `Handlers` instance
(`self.media_handlers = self._DEFAULT_HANDLERS`). Because the object was
shared by reference, customising one multipart parser's handler mapping
(removing, replacing or adding a media handler) silently mutated the mapping
every other parser in the same process saw, so unrelated uploads would start
failing to parse or would render parts with the wrong serializer.

Fix: `MultipartParseOptions.__init__` now starts each instance from its own
copy of the default handlers (`self._DEFAULT_HANDLERS.copy()`), and
`Handlers` gained a proper `copy()` method that returns a fresh `Handlers`
instance with the same keys and values but an independent resolver. Mutations
made through one parser's `media_handlers` now stay scoped to that parser,
and every new parser still starts from the two built-in handlers
(`application/json`, `application/x-www-form-urlencoded`).

Verification: the project's own pytest suite slice
(`python3 -m pytest tests/test_media_multipart.py tests/test_media_handlers.py
tests/test_media_urlencoded.py tests/test_mediatypes.py -q`) passes fully
with the upstream regression test for this bug
(`test_multipart_parse_options_default_handlers_unique`) planted into
`tests/test_media_multipart.py` from /opt/golden.
MD

# Prove the fix with the project's own machinery: plant the upstream
# regression test (golden bytes for tests/test_media_multipart.py from
# /opt/golden, already in the image) and run the media suite slice plus the
# regression test, offline.
cp /opt/golden/test_media_multipart.py tests/test_media_multipart.py
if ! python3 -m pytest -v \
        tests/test_media_multipart.py \
        tests/test_media_handlers.py \
        tests/test_media_urlencoded.py \
        tests/test_mediatypes.py \
        > /tmp/oracle_pytest.log 2>&1; then
    echo "oracle: pytest suite did not pass; tail:" >&2
    tail -40 /tmp/oracle_pytest.log >&2
    exit 1
fi
grep -q "test_multipart_parse_options_default_handlers_unique PASSED" /tmp/oracle_pytest.log || {
    echo "oracle: upstream regression test did not actually run and pass" >&2
    exit 1
}

# Leave the tree exactly as the verifier expects it: the regression test was
# planted here only to prove the fix and must not persist (the verifier
# re-plants it itself and asserts every tracked file except the fixed source
# files is byte-identical to the pinned commit).
git restore --worktree --source=HEAD -- tests/test_media_multipart.py || {
    echo "oracle: could not restore tests/test_media_multipart.py" >&2
    exit 1
}

echo "oracle: fix applied, summary written, media suite and regression test green"
exit 0