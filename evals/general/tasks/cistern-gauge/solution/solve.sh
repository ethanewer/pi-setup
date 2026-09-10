#!/bin/bash
# Oracle for cistern-gauge: applies the median-baseline change to the shipped
# reactor. The real solver lives in solution/solver.py; this wrapper installs
# it, runs it against the reactor identified by /app/pom.xml, then proves the
# result with an offline reactor build. It never reads /tests.
set -eu

cp /solution/solver.py /app/.apply_fix.py
python3 /app/.apply_fix.py /app/pom.xml
rm -f /app/.apply_fix.py

cd /app
mvn -o -q -B -f /app/pom.xml clean verify

echo "oracle applied the median baseline estimator; reactor is green offline"