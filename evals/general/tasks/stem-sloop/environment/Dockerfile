ARG UPSTREAM_SHA_PARENT=7731825df8008c3fa65096d2681952eddd3b0c2d
ARG UPSTREAM_SHA_FIX=76260d9b3c6acbabf9a8ddae11d4fff3985b6272

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

# Toolchain: JDK 21 (javac/java), git, curl. The whole task is javac-only:
# the guava source tree at this commit compiles with annotation jars, no
# Maven. git is needed by the build script for provenance assertions and by
# the agent for the project's own test running; curl only for the jar fetch.
RUN apt-get update \
 && apt-get install -y --no-install-recommends openjdk-21-jdk-headless git curl \
 && rm -rf /var/lib/apt/lists/* \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Compile-only annotation jars (the 2022-era guava sources import
# com.google.errorprone.annotations.InlineMe and guava-testlib imports
# .Keep) plus the test-framework jars the project's own JUnit tests use.
# error_prone_annotations is pinned to 2.11.0 = the tree's own pom pin; the
# mined 2.10.0 pin lacks Keep and guava-testlib will not compile with it.
RUN mkdir -p /opt/jars && cd /opt/jars \
 && for u in \
      "com/google/errorprone/error_prone_annotations/2.11.0/error_prone_annotations-2.11.0.jar" \
      "org/checkerframework/checker-qual/2.5.0/checker-qual-2.5.0.jar" \
      "com/google/j2objc/j2objc-annotations/1.3/j2objc-annotations-1.3.jar" \
      "com/google/code/findbugs/jsr305/3.0.2/jsr305-3.0.2.jar" \
      "org/codehaus/mojo/animal-sniffer-annotations/1.18/animal-sniffer-annotations-1.18.jar" \
      "com/google/guava/failureaccess/1.0.1/failureaccess-1.0.1.jar" \
      "junit/junit/4.13.2/junit-4.13.2.jar" \
      "org/hamcrest/hamcrest-core/1.3/hamcrest-core-1.3.jar" \
      "com/google/truth/truth/1.1.3/truth-1.1.3.jar" \
      "com/google/truth/extensions/truth-java8-extension/1.1.3/truth-java8-extension-1.1.3.jar" ; do \
   curl -fsSL -O "https://repo.maven.apache.org/maven2/$u" || { echo "FAILED to fetch $u"; exit 1; }; \
 done \
 && test "$(ls /opt/jars | wc -l)" = 10

# Clone the REAL upstream repository (google/guava) at exactly the parent
# commit, with the shallowest possible history: `git init` + one depth-1
# fetch of the pinned SHA means the object store in /app/src holds ONLY the
# parent commit. The fix commit (which an agent must not be able to look up
# or fetch) is NEVER fetched into this clone; it is asserted unreachable
# below. Ownership is fixed in this same RUN so no later chown layer
# duplicates the tree.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/google/guava.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit reachable in trial clone"; exit 1; \
    fi \
 && test "$(git rev-list --all | wc -l)" = 1 \
 && chown -R 1000:1000 /app/src \
 && echo "parent pinned at $(git rev-parse HEAD); single-commit store; fix unreachable"

# Bake a pristine PRE-FIX compile of guava/src (the parent tree) at
# /opt/prefix/classes, plus guava-testlib at /opt/prefix/testlib. The
# verifier runs the agent's own reproduction against these classes and
# requires it to FAIL, proving the symptom is real and the reproduction
# targets it. Compiled once here (approx 8s at 1 CPU) so the verifier and
# the trial never have to rebuild the pre-fix concept.
RUN mkdir -p /opt/prefix/classes /opt/prefix/testlib \
 && javac -d /opt/prefix/classes -cp "/opt/jars/*" \
      $(find /app/src/guava/src -name '*.java' | sort) > /tmp/prefix-src.log 2>&1; rc=$?; \
    tail -2 /tmp/prefix-src.log; \
    if [ $rc -ne 0 ]; then echo "PREFIX guava/src JAVAC FAILED"; exit 1; fi \
 && javac -d /opt/prefix/testlib -cp "/opt/jars/*:/opt/prefix/classes" \
      $(find /app/src/guava-testlib/src -name '*.java' | sort) > /tmp/prefix-testlib.log 2>&1; rc=$?; \
    if [ $rc -ne 0 ]; then echo "PREFIX guava-testlib JAVAC FAILED rc=$rc"; tail -20 /tmp/prefix-testlib.log; exit 1; fi \
 && test "$(find /opt/prefix/classes -name '*.class' | wc -l)" = 1967 \
 && test "$(find /opt/prefix/testlib -name '*.class' | wc -l)" = 606 \
 && echo "pre-fix classes: $(find /opt/prefix/classes -name '*.class' | wc -l) + $(find /opt/prefix/testlib -name '*.class' | wc -l)"

# Extract the project's OWN regression tests for this bug (the four graph
# test files the fix commit rewrote) into /opt/golden using a THROWAWAY
# clone under /tmp that is deleted immediately afterwards, so the fix
# object never enters /app/src and no upstream test bytes enter this task
# tree. /opt/golden therefore holds only upstream TEST source, never the
# fix itself.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/google/guava.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && for f in EndpointPairTest AbstractStandardUndirectedGraphTest \
             AbstractStandardUndirectedNetworkTest ValueGraphTest; do \
      git show ${UPSTREAM_SHA_FIX}:guava-tests/test/com/google/common/graph/$f.java \
        > /opt/golden/$f.java || exit 1; \
    done \
 && test -s /opt/golden/EndpointPairTest.java \
 && grep -q "endpointPair_undirected_contains" /opt/golden/EndpointPairTest.java \
 && grep -q "doesNotContain(EndpointPair.ordered(N1, N2))" /opt/golden/EndpointPairTest.java \
 && grep -q "putEdgeValue_undirected_orderMismatch" /opt/golden/ValueGraphTest.java \
 && grep -q "edgeConnectingOrNull_orderMismatch" /opt/golden/AbstractStandardUndirectedNetworkTest.java \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone \
 && if git -C /app/src cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit reachable in trial clone after golden extraction"; exit 1; \
    fi \
 && echo "golden tests extracted (4 files), throwaway clone deleted, fix still unreachable"

# Authored helper: RunOne runs exactly one JUnit test method by name and
# exits nonzero on failure. Used at build time for the parent-direction
# golden check and at verify time for method-level golden assertions.
RUN mkdir -p /opt/run \
 && cat > /opt/run/RunOne.java <<'JAVA'
import org.junit.runner.JUnitCore;
import org.junit.runner.Request;
import org.junit.runner.Result;
import org.junit.runner.Description;
import org.junit.runner.manipulation.Filter;
import org.junit.runner.notification.Failure;

public final class RunOne {
  static String method;

  public static void main(String[] args) {
    if (args.length != 2) {
      System.err.println("usage: RunOne <class> <method>");
      System.exit(3);
    }
    Class<?> c;
    try {
      c = Class.forName(args[0]);
    } catch (ClassNotFoundException e) {
      System.err.println("class not found: " + args[0]);
      System.exit(2);
      return;
    }
    method = args[1];
    // Guava's graph hierarchy runs each test under several configuration
    // variants, so a test's Description method name is
    // "<method>[<config>]"; match on prefix to cover every variant of the
    // requested method (and, being a prefix, never a different method).
    Filter f = new Filter() {
      @Override
      public boolean shouldRun(Description d) {
        if (d.isTest()) {
          return d.getMethodName() != null && d.getMethodName().startsWith(method);
        }
        for (Description child : d.getChildren()) {
          if (shouldRun(child)) {
            return true;
          }
        }
        return false;
      }

      @Override
      public String describe() {
        return "method " + method;
      }
    };
    Request req = new org.junit.internal.requests.ClassRequest(c);
    Result r = new JUnitCore().run(req.filterWith(f));
    System.out.println(
        "RunOne " + args[0] + "#" + args[1]
            + " tests=" + r.getRunCount() + " failures=" + r.getFailureCount());
    for (Failure x : r.getFailures()) {
      System.out.println(x.getTrace());
    }
    System.exit(r.wasSuccessful() && r.getRunCount() >= 1 ? 0 : 1);
  }
}
JAVA
RUN javac -cp /opt/jars/junit-4.13.2.jar -d /opt/run /opt/run/RunOne.java \
 && rm /opt/run/RunOne.java \
 && test -s /opt/run/RunOne.class

# Parent-direction confirmation 1/3 in THIS image, as the user the trial may
# run as (uid 1000): the direct reproduction compiled against the pristine
# pre-fix classes must FAIL with the contract violation (edges().contains
# reports true for an ordered pair no element equals).
RUN cat > /tmp/Repro5843.java <<'JAVA'
import com.google.common.graph.EndpointPair;
import com.google.common.graph.GraphBuilder;
import com.google.common.graph.MutableGraph;
import java.util.Set;

public class Repro5843 {
  public static void main(String[] args) {
    MutableGraph<Integer> g = GraphBuilder.undirected().build();
    g.putEdge(1, 2);
    Set<EndpointPair<Integer>> edges = g.edges();
    EndpointPair<Integer> ordered = EndpointPair.ordered(1, 2);
    boolean contains = edges.contains(ordered);
    boolean anyMatch = false;
    for (EndpointPair<Integer> e : edges) {
      if (e.equals(ordered)) anyMatch = true;
    }
    System.out.println("edges.contains(ordered(1,2)) = " + contains);
    System.out.println("any element equals ordered(1,2) = " + anyMatch);
    if (contains && !anyMatch) {
      System.out.println("CONTRACT VIOLATION: edges() claims to contain an ordered pair it does not");
      System.exit(1);
    }
    if (!contains && anyMatch) {
      System.out.println("CONTRACT VIOLATION (reverse): a present element is not reported by contains()");
      System.exit(1);
    }
    System.out.println("OK: contains() and membership agree");
  }
}
JAVA
RUN chmod 755 /tmp/Repro5843.java \
 && su -s /bin/bash ubuntu -c ' \
      javac -cp /opt/prefix/classes -d /tmp /tmp/Repro5843.java \
      && cd /tmp && timeout 30 java -cp /opt/prefix/classes:/tmp Repro5843' \
      > /tmp/repro-prefix.out 2>&1; rc=$?; \
    cat /tmp/repro-prefix.out; \
    if [ "$rc" -eq 0 ]; then echo "REPRO DID NOT FAIL ON PRE-FIX CLASSES - aborting"; exit 1; fi; \
    grep -q "CONTRACT VIOLATION" /tmp/repro-prefix.out \
      || { echo "violation message not seen"; exit 1; } \
 && echo "parent-direction 1/3 OK: direct repro fails against pre-fix classes"

# Parent-direction confirmation 2/3 in THIS image: the upstream regression
# test methods (extracted from the fix commit into /opt/golden) must FAIL
# against the pre-fix classes, proving the golden tests target exactly this
# bug. All four golden test files are compiled into /tmp/golden and the
# classpath puts /tmp/golden FIRST, so the JVM resolves the golden (post-fix
# assertion) versions of the classes even though the rest of the test
# directory was compiled from the parent tree.
RUN mkdir -p /opt/pcheck /tmp/golden \
 && javac -d /opt/pcheck -cp "/opt/jars/*:/opt/prefix/classes:/opt/prefix/testlib" \
      $(find /app/src/guava-tests/test/com/google/common/graph -name '*.java' | grep -v PackageSanityTests | sort) \
      > /tmp/pcheck.log 2>&1; rc=$?; \
    if [ $rc -ne 0 ]; then echo "PRE-FIX GRAPH TESTS JAVAC FAILED rc=$rc"; tail -20 /tmp/pcheck.log; exit 1; fi \
 && cp /opt/golden/*.java /tmp/golden/ \
 && cd /tmp/golden \
 && javac -d /tmp/golden -cp "/opt/jars/*:/opt/prefix/classes:/opt/prefix/testlib:/opt/pcheck" \
      EndpointPairTest.java ValueGraphTest.java \
      AbstractStandardUndirectedGraphTest.java AbstractStandardUndirectedNetworkTest.java \
      > /tmp/golden-javac.log 2>&1; rc=$?; \
    if [ $rc -ne 0 ]; then echo "GOLDEN JAVAC FAILED rc=$rc"; tail -20 /tmp/golden-javac.log; exit 1; fi \
 && cd /tmp && java -cp "/opt/run:/tmp/golden:/opt/jars/*:/opt/pcheck:/opt/prefix/classes:/opt/prefix/testlib" \
      RunOne com.google.common.graph.EndpointPairTest endpointPair_undirected_contains \
      > /tmp/golden-on-prefix.out 2>&1; rc=$?; \
    cat /tmp/golden-on-prefix.out; \
    if [ "$rc" -eq 0 ]; then echo "GOLDEN METHOD PASSED ON PRE-FIX CLASSES - aborting"; exit 1; fi; \
    grep -q "failures=1" /tmp/golden-on-prefix.out \
      || { echo "golden method did not fail as expected"; exit 1; } \
 && echo "parent-direction 2/3 OK: upstream regression method fails on pre-fix classes"

# Parent-direction confirmation 3/3 in THIS image: the whole compiled graph
# test directory with the golden (post-fix assertion) classes resolved
# first is ALSO run against the pre-fix classes and must fail, and the
# failure must be attributable to the bug's methods.
RUN cd /tmp && java -cp "/tmp/golden:/opt/jars/*:/opt/pcheck:/opt/prefix/classes:/opt/prefix/testlib" \
      org.junit.runner.JUnitCore \
      com.google.common.graph.EndpointPairTest \
      com.google.common.graph.ValueGraphTest \
      com.google.common.graph.StandardMutableUndirectedGraphTest \
      com.google.common.graph.StandardMutableUndirectedNetworkTest \
      > /tmp/junit-on-prefix.out 2>&1; rc=$?; \
    tail -4 /tmp/junit-on-prefix.out; \
    if [ "$rc" -eq 0 ]; then echo "SUITE PASSED ON PRE-FIX CLASSES - aborting"; exit 1; fi; \
    grep -qE "hasEdgeConnecting_undirected_mismatch|edgeValueOrDefault_undirected_mismatch|putEdgeValue_undirected_orderMismatch|endpointPair_undirected_contains|hasEdgeConnecting_mismatch|edgesConnecting_orderMismatch|edgeConnectingOrNull_orderMismatch" /tmp/junit-on-prefix.out \
      || { echo "suite failure not attributable to the bug's test methods"; exit 1; } \
 && echo "parent-direction 3/3 OK: project suite fails on pre-fix classes at the bug's methods"

# Record sha256 pins of the golden tests, of the pre-fix classes and jars,
# and of the build/test toolchain itself, so the verifier can detect
# substitution by a non-root agent. /opt is read-only for non-root
# afterwards.
RUN mkdir -p /opt/pins \
 && sha256sum /opt/golden/*.java > /opt/pins/golden.sha256 \
 && (cd /opt/prefix/classes && for f in $(find . -name '*.class' | sort); do sha256sum "$f"; done) > /opt/pins/prefix-classes.sha256 \
 && (cd /opt/prefix/testlib && for f in $(find . -name '*.class' | sort); do sha256sum "$f"; done) > /opt/pins/prefix-testlib.sha256 \
 && sha256sum /opt/jars/*.jar > /opt/pins/jars.sha256 \
 && sha256sum /opt/run/RunOne.class \
      /usr/lib/jvm/*/bin/javac /usr/lib/jvm/*/bin/java \
      /usr/bin/git /usr/bin/curl /usr/bin/bash /usr/bin/find /usr/bin/xargs /usr/bin/grep \
      > /opt/pins/toolchain.sha256 \
 && chmod 555 /opt/pins /opt/golden /opt/prefix /opt/run /opt/jars /opt/pcheck \
 && chmod 444 /opt/pins/*.sha256 /opt/golden/*.java /opt/run/RunOne.class \
 && sha256sum -c /opt/pins/golden.sha256 > /dev/null \
 && (cd /opt/prefix/classes && sha256sum -c /opt/pins/prefix-classes.sha256 > /dev/null) \
 && sha256sum -c /opt/pins/jars.sha256 > /dev/null \
 && echo "golden + pre-fix classes + jars + toolchain pinned"

# Final permissions: the tree is already owned by uid 1000 (chown ran in
# the clone RUN, so no later layer re-copies it); a root trial writes
# regardless. /app must be writable by uid 1000 for the deliverables.
COPY files/ /app/
RUN chmod a+rwX /app && chmod 644 /app/README-BUILD.md

WORKDIR /app

CMD ["/bin/bash"]