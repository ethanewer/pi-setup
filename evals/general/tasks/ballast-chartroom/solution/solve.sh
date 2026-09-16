#!/bin/bash
# Oracle for ballast-chartroom: applies the operator-only dependency guard to
# the trivy checkout at /app/src, then proves the fix with the project's own
# test runner on the conda parser scope, from the repaired tree.
set -e

python3 /solution/fix_conda_parser.py /app/src/pkg/dependency/parser/conda/environment/parse.go

echo "== reproduction after the fix =="
cd /app/src
export PATH=/opt/go/bin:$PATH CGO_ENABLED=0 GOEXPERIMENT=jsonv2
go test -v -short ./pkg/dependency/parser/conda/... 2>&1 | tail -40

echo "== oracle done =="