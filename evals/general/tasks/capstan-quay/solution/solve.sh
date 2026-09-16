#!/bin/bash
# Oracle for capstan-quay: fix the gohugoio/hugo checkout at /app/src so a
# front-matter-only page renders an EMPTY .RawContent, then prove it with the
# project's own regression test for this behaviour (the fix-commit version of
# hugolib/page_test.go, kept out of the tree at /opt/golden/).
set -e

SRC=/app/src

python3 /solution/apply_fix.py "$SRC"

echo "== upstream regression test (golden file from the fix commit) =="
cd "$SRC"
cp hugolib/page_test.go /tmp/tree_page_test.go
cp /opt/golden/page_test.go hugolib/page_test.go
go test -vet=off ./hugolib -run TestPageRawContent -v
rc=$?
cp /tmp/tree_page_test.go hugolib/page_test.go
rm -f /tmp/tree_page_test.go
exit $rc