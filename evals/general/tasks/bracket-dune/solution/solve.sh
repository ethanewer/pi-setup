#!/bin/bash
# Oracle for bracket-dune: applies the minimal upstream fix for the
# case-insensitive label-matcher prefix bug to the prometheus checkout at
# /app/src, then runs the project's own regression test against the tree.
set -e

python3 /solution/fix_matcher.py /app/src/model/labels/matcher.go

echo "== a case-insensitive matcher no longer advertises a byte prefix =="
cd /app/src && go test -v ./model/labels -run TestPrefix