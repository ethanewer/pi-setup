#!/bin/bash
# Oracle for bracket-cairn: apply the deterministic nested-class ordering fix
# (order classes declared in the same enclosing type by fully-qualified name
# hash with lexicographic tie-break, exactly like the project's own method and
# field sorters) to the junit5 checkout at /app/src, then demonstrate the fix
# with the project's own regression test for the bug.
set -e

cd /app/src

echo "== applying the fix =="
git apply --check /solution/nested-class-order.patch
git apply /solution/nested-class-order.patch
git diff --stat

echo
echo "== own suite (tree's ReflectionUtilsTests + ReflectionSupportTests) =="
./gradlew :platform-tests:test \
  --tests "org.junit.platform.commons.util.ReflectionUtilsTests" \
  --tests "org.junit.platform.commons.support.ReflectionSupportTests" \
  -Ptesting.enableJaCoCo=false --offline 2>&1 | tail -8

echo
echo "== framework's own regression test for the bug (swapped in from the fix "
echo "   revision, then restored; the final tree keeps only the source fix) =="
testfile=platform-tests/src/test/java/org/junit/platform/commons/util/ReflectionUtilsTests.java
cp "$testfile" /tmp/reflection-utils-tests.backup
cp /opt/golden/ReflectionUtilsTests.java "$testfile"
trap 'cp /tmp/reflection-utils-tests.backup "$testfile"; rm -f /tmp/reflection-utils-tests.backup' EXIT
./gradlew :platform-tests:test \
  --tests "org.junit.platform.commons.util.ReflectionUtilsTests" \
  -Ptesting.enableJaCoCo=false --offline 2>&1 | tail -8
cp /tmp/reflection-utils-tests.backup "$testfile"
rm -f /tmp/reflection-utils-tests.backup
trap - EXIT

echo
echo "== final tree state =="
git status --porcelain