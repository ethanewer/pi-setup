#!/bin/bash
# Reference implementation of the /app/reproduce.sh deliverable contract for
# hoy-moor (junit-team/junit5, issue #5098).
#
# The contract (what any correct agent submission must satisfy):
#   usage: reproduce.sh [CHECKOUT]
#   * CHECKOUT defaults to /app/src; it must be a checkout of the framework.
#   * The script stages its OWN demonstration test classes into the checkout's
#     jupiter-tests test source tree, runs the project's OWN test runner on
#     them (offline), and removes every file it staged before exiting.
#   * Exit 0  <=>  the demonstrated correct behaviour holds: an inherited
#     package-private test method from a superclass in a different package AND
#     a same-signature method declared by the subclass are BOTH discovered and
#     BOTH executed (2 of 2).
#   * Exit non-zero in every other case, including when the tree is unmodified
#     and the bug is present (only 1 of 2 discovered/executed).
#
# This is the exact reference the oracle installs at /app/reproduce.sh; it is
# also the contract the instruction states, so an agent may implement its own.

set -u

CHECKOUT="${1:-/app/src}"
cd "$CHECKOUT" || { echo "reproduce: cannot cd to $CHECKOUT" >&2; exit 2; }

REPRO_ROOT="jupiter-tests/src/test/java/org/junit/jupiter/engine/repro"
SRC_BASE="$CHECKOUT/$REPRO_ROOT"

cleanup() {
  rm -rf "$SRC_BASE"
}
trap cleanup EXIT

mkdir -p "$SRC_BASE/master"

cat > "$SRC_BASE/master/ReproMasterTestCase.java" <<'JAVA'
/*
 * Superclass in a different package than its subclass, declaring a
 * package-private test method.
 */

package org.junit.jupiter.engine.repro.master;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInfo;
import org.junit.jupiter.api.TestReporter;

public class ReproMasterTestCase {

	@Test
	void test(TestInfo testInfo, TestReporter reporter) {
		reporter.publishEntry("reproSuper", testInfo.getTestMethod().orElseThrow().toGenericString());
	}

}
JAVA

cat > "$SRC_BASE/ReproChildTestCase.java" <<'JAVA'
/*
 * Subclass in a different package, declaring a method with the same name and
 * parameter list as the inherited package-private test method. Per Java
 * visibility rules this is NOT an override: both methods must run.
 */

package org.junit.jupiter.engine.repro;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInfo;
import org.junit.jupiter.api.TestReporter;
import org.junit.jupiter.engine.repro.master.ReproMasterTestCase;

@SuppressWarnings("JUnitMalformedDeclaration")
public class ReproChildTestCase extends ReproMasterTestCase {

	// @Override -- deliberately NOT an override: the inherited method is
	// package-private and declared in a different package.
	@Test
	void test(TestInfo testInfo, TestReporter reporter) {
		reporter.publishEntry("reproChild", testInfo.getTestMethod().orElseThrow().toGenericString());
	}

}
JAVA

cat > "$SRC_BASE/PackagePrivateMethodReproductionTests.java" <<'JAVA'
/*
 * Driver for the reproduction: discovers and executes the demonstration test
 * class through the project's own engine and requires BOTH methods to be
 * discovered and BOTH to run. Fails (non-zero) while the bug is present.
 */

package org.junit.jupiter.engine.repro;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.platform.commons.util.CollectionUtils.getOnlyElement;

import java.util.List;
import java.util.Map;
import java.util.stream.Stream;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInfo;
import org.junit.jupiter.api.TestReporter;
import org.junit.jupiter.engine.AbstractJupiterTestEngineTests;
import org.junit.jupiter.engine.repro.master.ReproMasterTestCase;
import org.junit.platform.engine.reporting.ReportEntry;
import org.junit.platform.testkit.engine.EngineExecutionResults;

class PackagePrivateMethodReproductionTests extends AbstractJupiterTestEngineTests {

	@Test
	void inheritedPackagePrivateTestMethodIsNotSilentlyDropped() throws Exception {
		var discoveryResults = discoverTestsForClass(ReproChildTestCase.class);
		var classDescriptor = getOnlyElement(discoveryResults.getEngineDescriptor().getChildren());

		assertThat(classDescriptor.getChildren()).hasSize(2);

		var results = executeTestsForClass(ReproChildTestCase.class);
		results.testEvents().assertStatistics(stats -> stats.started(2).succeeded(2));

		List<Map<String, String>> entries = allReportEntries(results).toList();
		assertThat(entries).containsExactlyInAnyOrder(
			Map.of("reproSuper",
				ReproMasterTestCase.class.getDeclaredMethod("test", TestInfo.class, TestReporter.class)
						.toGenericString()),
			Map.of("reproChild",
				ReproChildTestCase.class.getDeclaredMethod("test", TestInfo.class, TestReporter.class)
						.toGenericString()));
	}

	private static Stream<Map<String, String>> allReportEntries(EngineExecutionResults results) {
		return results.allEvents().reportingEntryPublished() //
				.map(event -> event.getRequiredPayload(ReportEntry.class)) //
				.map(ReportEntry::getKeyValuePairs);
	}

}
JAVA

echo "== running the framework's own test runner (offline) on the staged demonstration =="
if ./gradlew :jupiter-tests:test \
    --tests "org.junit.jupiter.engine.repro.PackagePrivateMethodReproductionTests" \
    -Ptesting.enableJaCoCo=false --offline > /tmp/repro-gradle.log 2>&1; then
  echo
  echo "REPRODUCED-BEHAVIOUR=OK: both methods were discovered and executed (2 of 2)."
  echo "This tree behaves correctly."
  tail -8 /tmp/repro-gradle.log
  exit 0
else
  rc=$?
  echo
  echo "REPRODUCTION-FAILED (gradle exit $rc): the demonstrated correct behaviour does"
  echo "not hold on this tree."
  echo "On the unmodified pinned commit this is the BUG: the inherited package-private"
  echo "test method is silently dropped, so only 1 of 2 tests is discovered/executed."
  echo "After a correct fix this script must exit 0."
  echo
  echo "--- relevant gradle output ---"
  tail -30 /tmp/repro-gradle.log
  exit $rc
fi