#!/bin/bash
# Own failing reproduction for the gzip FEXTRA header-field bug (kelson-current).
# Contract:
#   - runs the reproduction test class ReproTest through the codec-compression
#     module's test runner, fully offline (Maven local repo pre-warmed);
#   - prints the full Maven/surefire output and nothing else;
#   - exits 0 iff the reproduction test ran and passed
#     ("Tests run: N, Failures: 0, Errors: 0" with N >= 1).
# On the UNFIXED tree this script must exit nonzero: the correct bytes throw
# a DecompressionException and surefire reports the failing test.
set -u
cd /app/src || exit 1
mvn -o -pl codec-compression test \
    -Dtest=ReproTest \
    -Dsurefire.failIfNoSpecifiedTests=true \
    -Dcheckstyle.skip=true \
    -Dxml.format.skip=true \
    -Dlicense.skip=true \
    > /tmp/repro_run.log 2>&1
rc=$?
cat /tmp/repro_run.log
[ "$rc" -eq 0 ] || exit 1
grep -qE 'Tests run: [1-9][0-9]*[,] Failures: 0[,] Errors: 0[,] Skipped: [0-9]+' /tmp/repro_run.log || exit 1
exit 0