#!/bin/bash
# Oracle for dory-reach: writes the agent deliverable reproduction (a failing
# Go test + fixture), applies the PEP 503 normalization fix to the trivy
# checkout at /app/src, then proves the result with the project's own test
# runner on the Python dependency parser scope, from the repaired tree.
set -e

chown -R 1000:1000 /app/src 2>/dev/null || true

cp /solution/repro_test.go /app/src/pkg/dependency/parser/python/pyproject/repro_test.go
cp /solution/repro.toml /app/src/pkg/dependency/parser/python/pyproject/testdata/repro.toml
python3 /solution/fix_pyproject.py /app/src/pkg/dependency/parser/python/pyproject/pyproject.go

echo "== reproduction + python parser suite after the fix =="
cd /app/src
export PATH=/opt/go/bin:$PATH CGO_ENABLED=0 GOEXPERIMENT=jsonv2
go test -v -short ./pkg/dependency/parser/python/... 2>&1 | tail -40

echo "== oracle done =="