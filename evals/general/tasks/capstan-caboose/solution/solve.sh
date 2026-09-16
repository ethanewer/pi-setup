#!/bin/bash
# Oracle for capstan-caboose: applies the real two-hunk upstream fix for the
# maven module's false activation (starship/starship issue #7426) to the
# checkout at /app/src, writes /app/summary.md, and proves the fix with the
# project's own test harness: the upstream regression test for the bug
# (extracted at image build time into /opt/golden, never part of this task
# tree) is planted into the inline `mod tests` block of src/modules/maven.rs,
# the maven-module unit tests are rebuilt and run offline, and the tree is
# restored to exactly fix-applied state. Reads only /app, /solution, /opt.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }
export PATH=/opt/cargo/bin:$PATH

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to the checked-out tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied maven false-activation fix patch"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: the maven module activated in any directory that merely contains an
`.mvn` folder, because the module's default detection list contained
`.mvn` and the project check did not distinguish a bare `.mvn` directory
(for example a user-level maven config dir holding only
`.mvn/maven.config`) from a real Maven project. Rendering the prompt
there produced an empty `via` tag with the maven symbol.

Fix: the `.mvn` folder was removed from the module's default
`detect_folders`, and the project check now also recognises the presence
of `.mvn/wrapper/maven-wrapper.properties` (in the current directory or,
when `recursive` is enabled, an ancestor directory) as a real Maven
project. A directory must now contain a `pom.xml` or a Maven wrapper
properties file for the module to show.

Verification: `cargo test --locked --offline -- maven` (the project's own
unit tests in the maven module's inline `mod tests`, including the
upstream regression test for this bug planted from /opt/golden) is green.
Reproducing the original symptom on the fixed tree:

    mkdir -p /tmp/proj/.mvn && touch /tmp/proj/.mvn/maven.config
    STARSHIP_CONFIG=/tmp/mvn.cfg /app/src/target/debug/starship prompt --path /tmp/proj

prints nothing, where the pinned tree printed `via` plus the maven symbol.
MD

# Prove the fix with the project's own machinery: save the fixed maven.rs,
# plant the upstream regression test (golden bytes already in the image),
# rebuild and run the maven-module test set, then put the fixed file back so
# the only change left in the tree is the fix itself.
cp src/modules/maven.rs /tmp/maven.oracle.before
if ! grep -q "fn folder_with_maven_config_does_not_trigger_module(" src/modules/maven.rs; then
    sed -i '/^mod tests {$/r /opt/golden/maven_test.rs' src/modules/maven.rs
fi
if ! cargo test --locked --offline -- maven > /tmp/oracle_test.log 2>&1; then
    tail -40 /tmp/oracle_test.log >&2
    cp /tmp/maven.oracle.before src/modules/maven.rs
    echo "oracle: maven-module tests failed after the fix" >&2
    exit 1
fi
cp /tmp/maven.oracle.before src/modules/maven.rs

echo "oracle: fix applied, summary written, maven-module tests green (incl. planted upstream regression test)"
exit 0