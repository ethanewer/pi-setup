#!/bin/bash
# Oracle for ballast-caboose: applies the boundary-containment fix to the
# character-range utility in the commons-lang checkout (/app/src), re-runs
# the reproduction, and runs the upstream regression test extracted into
# /opt/golden/ at image build time, plus the project's own test classes that
# exercise the utility.
set -e

python3 /solution/fix_char_range.py /app/src/src/main/java/org/apache/commons/lang3/CharRange.java

echo "== reproduction output after the fix =="
/app/probe.sh

echo "== upstream regression test =="
cp /opt/golden/CharRangeTest.java /app/src/src/test/java/org/apache/commons/lang3/CharRangeTest.java
cd /app/src
/opt/apache-maven-3.9.9/bin/mvn -B -q test \
  -Dtest='CharRangeTest#testContains_Charrange_negatedArgumentTouchingBounds' -DfailIfNoTests=false \
  -Dspotless.check.skip=true -Dcheckstyle.skip=true -Drat.skip=true -Denforcer.skip=true \
  -Dmaven.repo.local=/opt/m2repo

echo "== project's own test classes around the utility =="
/opt/apache-maven-3.9.9/bin/mvn -B -q test \
  -Dtest='CharRangeTest,CharSetTest,RangeTest,IntegerRangeTest,LongRangeTest,DoubleRangeTest' -DfailIfNoTests=false \
  -Dspotless.check.skip=true -Dcheckstyle.skip=true -Drat.skip=true -Denforcer.skip=true \
  -Dmaven.repo.local=/opt/m2repo

echo "== oracle done =="