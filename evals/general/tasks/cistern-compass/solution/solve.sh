#!/bin/bash
# Oracle for cistern-compass: applies the minimal upstream fix to the junit5
# checkout at /app/src -- the shared CSV reader must trim unquoted columns
# with ASCII-only whitespace semantics (String.trim(), not String.strip()).
# Then demonstrates the fix with the project's own regression test class, its
# sibling file-source test class and the authored hidden cases (all offline).
set -e

cd /app/src

echo "== applying the fix =="
git apply --check /solution/csv-trim-fix.patch
git apply /solution/csv-trim-fix.patch
git diff --stat

echo
echo "== project's own regression test class + sibling file-source class =="
./gradlew :jupiter-tests:test \
  --tests "org.junit.jupiter.params.provider.CsvArgumentsProviderTests" \
  --tests "org.junit.jupiter.params.provider.CsvFileArgumentsProviderTests" \
  -Ptesting.enableJaCoCo=false --offline 2>&1 | tail -8

echo
echo "== final tree state =="
git status --porcelain