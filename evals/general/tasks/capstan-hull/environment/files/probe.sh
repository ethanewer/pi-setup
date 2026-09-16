#!/bin/bash
# Reproduction probe for the spurious fraction-multiplication overflow.
# Compiles the project's Fraction utility together with FractionProbe.java
# and runs the checks. Exits 0 only when every check passes.
set -u
cd /app/src || exit 2
rm -rf /tmp/probe
mkdir -p /tmp/probe
javac -d /tmp/probe /app/FractionProbe.java \
    src/main/java/org/apache/commons/lang3/math/Fraction.java || exit 3
java -cp /tmp/probe org.apache.commons.lang3.math.FractionProbe