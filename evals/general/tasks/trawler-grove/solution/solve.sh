#!/bin/bash
# Oracle for trawler-grove: writes the two declared deliverables, applies
# the minimal upstream fix to the poetry checkout at /app/src (assign the
# removeprefix results so explicit refs/heads/... and refs/tags/...
# revisions are normalized to bare branch/tag names before `git checkout`),
# then proves the fix with the reproduction and the project's own suite.
set -e

echo "== deliverable 1: the failing reproduction =="
cp /solution/repro_test.py /app/repro_test.py
test -s /app/repro_test.py

echo "== deliverable 2: summary =="
cat > /app/summary.md <<'MD'
# trawler-grove summary

## Symptom
Git dependencies pinned to an explicit plumbing ref (refs/heads/<branch> or
refs/tags/<tag>) are never checked out correctly: `git checkout` is invoked
with the raw prefixed string, so the clone either fails with a checkout
error or lands on the wrong revision.

## Root cause
In the clone-fallback routine, the revision handed to checkout was supposed
to be normalized by stripping a leading refs/heads/ or refs/tags/ prefix,
but the normalization silently did nothing: both `str.replace` calls
discarded their results (str.replace returns a new string; the caller never
assigned it back to the revision variable), and the branch prefix was also
misspelled ("refs/head/" instead of "refs/heads/"). Non-prefixed revisions
were unaffected, so only explicit refs/... pins hit the bug.

## Change
src/poetry/vcs/git/backend.py: assign the stripped revision, using
`revision = revision.removeprefix("refs/heads/")` and
`revision = revision.removeprefix("refs/tags/")` before checkout, so
refs/heads/main -> main and refs/tags/v1.0 -> v1.0 while plain revisions
pass through unchanged.
MD
test -s /app/summary.md

echo "== apply the fix =="
python3 /solution/patch_backend.py /app/src/src/poetry/vcs/git/backend.py

echo "== reproduction must now pass =="
cd /app
/opt/poetry-venv/bin/python -m pytest /app/repro_test.py \
    --no-header -p no:randomly -o addopts=""

echo "== the project's own git-backend suite =="
cd /app/src
/opt/poetry-venv/bin/python -m pytest tests/vcs/git/test_backend.py \
    --no-header -p no:randomly -o addopts="" -q