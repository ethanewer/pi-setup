#!/bin/bash
# Oracle for capstan-hull: applies the spurious-overflow fix to
# Fraction.multiplyBy in the commons-lang checkout (/app/src), writes the
# summary deliverable, re-runs the reproduction probe, and runs the upstream
# regression test extracted into /opt/golden/ at image build time plus the
# project's own math test classes.
set -e

python3 /solution/fix_fraction.py /app/src/src/main/java/org/apache/commons/lang3/math/Fraction.java

cat > /app/summary.md <<'EOF'
# Fix summary

Bug: `Fraction.multiplyBy` cancelled common factors only across the two
operands (Knuth 4.5.1 cross-gcd) and implicitly assumed each operand was
already reduced to lowest terms. A factor shared inside one unreduced
operand therefore survived into the intermediate int product and could
throw `ArithmeticException: overflow: mulPos` even when the reduced result
fitted in an int (e.g. -1/46341 * 100/1000000 = -1/463410000).

Fix: reduce both operands into locals first (gcd of each
numerator/denominator pair), then apply the same cross-gcd cancellation, so
an internal factor can no longer overflow the intermediate products.
divideBy and pow route through multiplyBy and are fixed as well; a product
whose reduced value genuinely exceeds Integer.MAX_VALUE still throws.
EOF

echo "== reproduction output after the fix =="
/app/probe.sh

echo "== upstream regression test =="
cp /opt/golden/FractionTest.java /app/src/src/test/java/org/apache/commons/lang3/math/FractionTest.java
cd /app/src
/opt/apache-maven-3.9.9/bin/mvn -B -q test \
  -Dtest='FractionTest#testMultiply+testDivide' -DfailIfNoTests=false \
  -Dspotless.check.skip=true -Dcheckstyle.skip=true -Drat.skip=true -Denforcer.skip=true \
  -Dmaven.repo.local=/opt/m2repo

echo "== project's own test classes around the utility =="
/opt/apache-maven-3.9.9/bin/mvn -B -q test \
  -Dtest='FractionTest,FractionReadObjectTest,NumberUtilsTest,IEEE754rUtilsTest' -DfailIfNoTests=false \
  -Dspotless.check.skip=true -Dcheckstyle.skip=true -Drat.skip=true -Denforcer.skip=true \
  -Dmaven.repo.local=/opt/m2repo

echo "== oracle done =="