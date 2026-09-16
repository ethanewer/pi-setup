#!/bin/bash
# Oracle for hoy-moor: repair the junit5 checkout at /app/src against the real
# upstream bug (a package-private test method inherited from a superclass in a
# different package must not be silently dropped when a subclass declares a
# same-signature method; issue #5098) and install the /app/reproduce.sh
# deliverable that demonstrates the bug through the framework's own runner.
set -e

cd /app/src

echo "== installing the /app/reproduce.sh deliverable =="
cp /solution/reproduce.sh /app/reproduce.sh
chmod +x /app/reproduce.sh

echo
echo "== applying the fix (upstream change set for the discovery/selector pipeline) =="
git apply --check /solution/fix.patch
git apply /solution/fix.patch
git diff --stat

echo
echo "== demonstrating with the deliverable reproduction (must print 2 of 2 and exit 0) =="
/app/reproduce.sh

echo
echo "== tree's own engine slice (must stay green) =="
./gradlew :jupiter-tests:test \
  --tests "org.junit.jupiter.engine.LifecycleMethodOverridingTests" \
  --tests "org.junit.jupiter.engine.OverloadedTestMethodTests" \
  --tests "org.junit.jupiter.engine.discovery.DiscoverySelectorResolverTests" \
  --tests "org.junit.jupiter.engine.discovery.DiscoveryTests" \
  -Ptesting.enableJaCoCo=false --offline 2>&1 | tail -8

echo
echo "== final tree state =="
git status --porcelain