#!/bin/bash
# Oracle for deadwood-shoal: applies the minimal upstream fix (guard the four
# pad overloads so a requested size not greater than the string length returns
# the string unchanged) and writes the /app/repro/PadRepro.java deliverable,
# then recompiles the module to prove the tree still builds.
set -e

mkdir -p /app/repro
cp /solution/PadRepro.java /app/repro/PadRepro.java

python3 /solution/fix_pad_guard.py \
  /app/src/src/main/java/org/apache/commons/lang3/StringUtils.java

cd /app/src
mvn -B -q test-compile \
  -Dspotless.check.skip=true -Dcheckstyle.skip=true \
  -Drat.skip=true -Denforcer.skip=true

echo "ORACLE OK: fix applied, repro in place, module recompiles"