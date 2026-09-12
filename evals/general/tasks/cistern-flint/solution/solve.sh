#!/bin/bash
# Oracle for cistern-flint: applies the relabel empty-value round-trip fix to
# the prometheus checkout (/app/src) and proves the project's own relabel
# package tests still pass with it.
set -e

python3 /solution/fix_relabel.py /app/src/model/relabel/relabel.go

echo "== project's own relabel package tests after the fix =="
cd /app/src
go test -v ./model/relabel