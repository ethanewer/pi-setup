#!/bin/bash
# Verifier for cistern-channel: proves the agent's fix in the real
# falconry/falcon tree at /app/src by (1) asserting provenance (HEAD still
# the pinned parent commit, every tracked file except the two media files the
# bug's root cause lives in is byte-identical to it, no stray untracked
# files, no unreachable objects), (2) asserting the installed falcon imports
# from /app/src, (3) requiring /app/summary.md, (4) planting the upstream
# project's own regression test for this bug (tests/test_media_multipart.py
# as at the fix commit, extracted at image build time into /opt/golden) plus
# three authored hidden test modules, and (5) running pytest on the media
# suite slice with every required test demanded to have run AND passed.
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

PARENT=1f914c5143250c1113089868f30eed67697dc40d
# sha256 of tests/test_media_multipart.py exactly as it exists at the fix
# commit cae50da40454a361fec84e58d4b44bedc5b6c0cd (the bytes extracted into
# /opt/golden at image build time). The trial runs as root in this shared
# container, so the agent COULD rewrite the baked-in golden file; pin it so a
# tampered test can never vouch for a broken fix.
GOLDEN_SHA256=705befebac0c1bd7b68e4f72e3e2c1884b91bdb439e15abe3bd992f1dfe3c114

cd /app/src || fail "/app/src is missing"

# 1) the tree must still be at the pinned parent commit (no commits added,
#    and nothing can hide work from the blob-level scope check below).
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi
if [ "$(git rev-list HEAD --count)" != "1" ]; then
    fail "clone contains history beyond the pinned parent commit"
fi

# 2) the installed library must be the agent's tree, not a stale copy.
if ! python3 -c "import falcon; assert falcon.__file__.startswith('/app/src/'), falcon.__file__"; then
    fail "import falcon does not resolve to /app/src (got $(python3 -c 'import falcon; print(falcon.__file__)' 2>/dev/null))"
fi

# 3) scope: every change must live in exactly the source files the bug is in
#    (the multipart parse-options constructor and/or the Handlers class,
#    discovered by the agent, not named here). This is a CONTENT check, not a
#    git-status check: we hash the actual bytes of every tracked file on disk
#    against the pinned commit's own blob, so assume-unchanged/skip-worktree
#    tricks cannot hide a dirty file, and we refuse any untracked
#    non-ignored file.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        falcon/media/multipart.py|falcon/media/handlers.py) : ;;
        *)
            want=$(git rev-parse "$PARENT:$f" 2>/dev/null || true)
            have=$(git hash-object -- "$f" 2>/dev/null || true)
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
    fail "working tree modified outside the bug's source files (see $LOG)"
fi

# 4) belt: the fix must actually be present in the working tree (at least one
#    of the two allowed source files must differ from the pinned blob).
changed=0
for f in falcon/media/multipart.py falcon/media/handlers.py; do
    if [ "$(git hash-object -- "$f" 2>/dev/null)" != "$(git rev-parse "$PARENT:$f" 2>/dev/null)" ]; then
        changed=1
    fi
done
if [ "$changed" != "1" ]; then
    fail "no change in falcon/media/multipart.py or falcon/media/handlers.py ($LOG)"
fi

# 5) belt: the object store must hold nothing beyond the pinned parent commit
#    (no sneaked-in upstream commit, no hidden modifications).
unreachable=$(git fsck --no-reflogs --unreachable 2>&1 | wc -l)
if [ "$unreachable" != "0" ]; then
    fail "object store contains unreachable objects (see fsck)"
fi

# 6) deliverable: the agent's own change summary must exist.
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 7) plant the upstream regression test (golden bytes of
#    tests/test_media_multipart.py from the fix commit, extracted at image
#    build time; never part of this task tree) and the three authored hidden
#    test modules into the test tree.
have=$(sha256sum /opt/golden/test_media_multipart.py 2>/dev/null | awk '{print $1}')
if [ "$have" != "$GOLDEN_SHA256" ]; then
    fail "golden regression test is missing or tampered (sha256=${have:-none})"
fi
cp /opt/golden/test_media_multipart.py tests/test_media_multipart.py || fail "cannot plant golden regression test"
cp /tests/hidden/replace-isolated/test_zz_replace_isolated.py tests/test_zz_replace_isolated.py || fail "cannot plant hidden case 1"
cp /tests/hidden/fresh-instance/test_zz_fresh_instance.py tests/test_zz_fresh_instance.py || fail "cannot plant hidden case 2"
cp /tests/hidden/form-handler-api/test_zz_form_handler_api.py tests/test_zz_form_handler_api.py || fail "cannot plant hidden case 3"

# 8) run pytest on the media suite slice plus the planted tests, offline.
# Run pytest with python3 -S so the interpreter never imports `site` and
# cannot execute a stray sitecustomize.py or *.pth from site-packages: the
# trial runs as root in this shared container, so an agent could otherwise
# monkeypatch falcon at import time (fixing the bug outside /app/src) and
# let an unfixed tree pass. site-packages is put on PYTHONPATH explicitly so
# pytest and its plugins still resolve; falcon itself comes from /app/src.
SITE_PKGS=$(python3 -c 'import site; print(site.getsitepackages()[0])')
if ! PYTHONPATH="/app/src:$SITE_PKGS" python3 -S -m pytest -v \
        tests/test_media_multipart.py \
        tests/test_media_handlers.py \
        tests/test_media_urlencoded.py \
        tests/test_mediatypes.py \
        tests/test_zz_replace_isolated.py \
        tests/test_zz_fresh_instance.py \
        tests/test_zz_form_handler_api.py \
        > "$LOG.pytest" 2>&1; then
    tail -60 "$LOG.pytest" >&2
    fail "pytest suite did not pass (see $LOG.pytest)"
fi

# 9) belt: every required test must actually have RUN and PASSED (a
#    skipped/neutralised run or a sabotaged file would leave no PASSED line).
for t in \
    test_multipart_parse_options_default_handlers_unique \
    test_replacing_a_handler_on_one_parser_is_isolated \
    test_fresh_parser_created_after_mutation_is_unaffected \
    test_del_through_form_handler_api_is_isolated; do
    if ! grep -q "::${t} PASSED" "$LOG.pytest"; then
        fail "required test ${t} did not run and pass (see $LOG.pytest)"
    fi
done

echo 1 > /logs/verifier/reward.txt
exit 0