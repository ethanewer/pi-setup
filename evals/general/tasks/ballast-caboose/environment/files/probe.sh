#!/bin/bash
# Reproduction probe for the character-range containment bug.
# Compiles the range utility together with Probe.java and runs the checks.
# Exits 0 only when every containment check passes.
set -u
cd /app/src || exit 2
rm -rf /tmp/probe
mkdir -p /tmp/probe
javac -d /tmp/probe /app/Probe.java src/main/java/org/apache/commons/lang3/CharRange.java || exit 3
java -cp /tmp/probe org.apache.commons.lang3.Probe