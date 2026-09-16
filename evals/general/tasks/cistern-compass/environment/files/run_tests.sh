#!/bin/bash
# Convenience wrapper: run the jupiter-tests CSV provider slice exactly like the
# verifier does (offline; the trial has no network). FAILS at the pinned commit
# because the regression test is present and the bug is real; it must be GREEN
# once the underlying bug is fixed.
set -e
cd /app/src
exec ./gradlew :jupiter-tests:test \
  --tests "org.junit.jupiter.params.provider.CsvArgumentsProviderTests" \
  -Ptesting.enableJaCoCo=false --offline