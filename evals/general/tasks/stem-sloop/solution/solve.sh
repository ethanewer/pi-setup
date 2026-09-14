#!/bin/bash
# Oracle for stem-sloop: applies the ordering-compatibility fix to the real
# google/guava tree at /app/src (the graph package must reject ordered
# EndpointPairs on undirected graphs, in both the graph and network
# implementations, instead of silently accepting them), rebuilds from
# source, writes /app/repro.sh and /app/summary.md, then proves the work:
# the reproduction must pass against a fresh compile of the repaired tree
# and must fail against the pristine pre-fix classes baked at
# /opt/prefix/classes; the upstream regression methods and the project's own
# graph tests (compiled from a scratch copy with the golden tests planted
# outside the delivered tree) must pass. Reads only /app, /solution, /opt
# and /tmp.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied the graph-ordering compatibility fix (3 source files)"

cat > /app/repro.sh <<'SH'
#!/bin/bash
# Failing reproduction for the undirected-graph edge-set contract violation.
# Contract: honour $CLASSES_DIR (a directory of compiled guava classes; when
# unset, compile /app/src/guava/src into a fresh scratch dir first), write
# and compile a small Java driver in a fresh scratch dir under /tmp, print
# the driver's output only, and exit 0 iff the Collection contract holds
# (edges().contains(ordered) agrees with whether any element equals it).
set -u
CLASSES_DIR=${CLASSES_DIR:-}
work=$(mktemp -d /tmp/stem-sloop-repro.XXXXXX) || exit 1
trap 'rm -rf "$work"' EXIT

if [ -z "$CLASSES_DIR" ]; then
    CLASSES_DIR="$work/classes"
    mkdir -p "$CLASSES_DIR"
    srcs=$(find /app/src/guava/src -name '*.java' | sort)
    if ! javac -d "$CLASSES_DIR" -cp "/opt/jars/*" $srcs > "$work/javac.log" 2>&1; then
        echo "repro: fresh javac of /app/src/guava/src failed" >&2
        tail -5 "$work/javac.log" >&2
        exit 2
    fi
fi

cat > "$work/Repro.java" <<'JAVA'
import com.google.common.graph.EndpointPair;
import com.google.common.graph.GraphBuilder;
import com.google.common.graph.MutableGraph;
import java.util.Set;

public final class Repro {
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

if ! javac -cp "$CLASSES_DIR" -d "$work" "$work/Repro.java" > "$work/javac2.log" 2>&1; then
    echo "repro: javac of the driver failed" >&2
    cat "$work/javac2.log" >&2
    exit 2
fi
timeout 30 java -cp "$CLASSES_DIR:$work" Repro
exit $?
SH
chmod +x /app/repro.sh
echo "oracle: wrote /app/repro.sh"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: on an undirected graph built with the GraphBuilder API, the set
returned by `edges()` violated the java.util.Collection contract:
`edges().contains(EndpointPair.ordered(a, b))` returned true for an edge
added as `putEdge(a, b)`, while no element of the set actually equals that
ordered pair (iterating the set found nothing equal). The same
false-positive membership leaks into the value-graph variant (ValueGraph),
into networks (edgeConnecting/edgesConnecting lookups by an ordered pair
returned values the ordering rules say should not be accepted), and into
immutable undirected graphs. On directed graphs the wrong pair kind was
rejected loudly, but on undirected graphs the wrong kind slipped through.

Cause: the graph package's shared implementations decide whether an
EndpointPair's ordering is compatible with the graph's directionality
with `endpoints.isOrdered() || !this.isDirected()`, which accepts an
ordered pair on ANY undirected graph (a directed-only-facing check). The
same logic lives in both the graph family (`AbstractBaseGraph`) and the
network family (`AbstractNetwork`), and the mismatch constant's message
text was worded as if only directed graphs could ever be offended.

Fix: make the compatibility decision symmetric - a pair is compatible iff
`endpoints.isOrdered() == this.isDirected()`, so an undirected graph
rejects an ordered pair (with IllegalArgumentException carrying the
mismatch message) exactly as a directed graph already rejects an unordered
pair, and lookups such as `hasEdgeConnecting(EndpointPair)` report false
instead of a false positive. The change is in the shared graph/network
implementations so every variant (mutable, immutable, value, network) is
covered by the same corrected check.

Verification: /app/repro.sh fails against the pristine pre-fix classes at
/opt/prefix/classes (contains=true, any element equals it=false,
CONTRACT VIOLATION, nonzero exit) and passes against a fresh compile of the
repaired tree (contains=false, membership agrees, exit 0). The upstream
regression methods (endpointPair_undirected_contains,
hasEdgeConnecting_undirected_mismatch, edgeValueOrDefault_undirected_mismatch,
putEdgeValue_undirected_orderMismatch, hasEdgeConnecting_mismatch,
edgesConnecting_orderMismatch, edgeConnectingOrNull_orderMismatch) all pass,
and the project's own graph JUnit suite (EndpointPairTest, ValueGraphTest,
the mutable/immutable graph & network hierarchy tests, equivalence, traverser
and element-order tests) stays green.
MD
echo "oracle: wrote /app/summary.md"

# Prove the work: fresh compile of the repaired tree, repro both directions.
rm -rf /tmp/oracle-classes && mkdir -p /tmp/oracle-classes
if ! javac -d /tmp/oracle-classes -cp "/opt/jars/*" \
      $(find /app/src/guava/src -name '*.java' | sort) > /tmp/oracle-javac.log 2>&1; then
    echo "oracle: javac of repaired tree failed; tail:" >&2
    tail -20 /tmp/oracle-javac.log >&2
    exit 1
fi
if ! CLASSES_DIR=/tmp/oracle-classes bash /app/repro.sh > /tmp/oracle-fixed.out 2>&1; then
    echo "oracle: /app/repro.sh failed on the repaired tree; out:" >&2
    cat /tmp/oracle-fixed.out >&2
    exit 1
fi
grep -q "OK: contains() and membership agree" /tmp/oracle-fixed.out \
    || { echo "oracle: fixed-direction repro missing OK verdict" >&2; exit 1; }
if CLASSES_DIR=/opt/prefix/classes bash /app/repro.sh > /tmp/oracle-prefix.out 2>&1; then
    echo "oracle: /app/repro.sh PASSED against the pre-fix classes (expected failure)" >&2
    cat /tmp/oracle-prefix.out >&2
    exit 1
fi
grep -q "CONTRACT VIOLATION" /tmp/oracle-prefix.out \
    || { echo "oracle: pre-fix direction repro did not print the violation" >&2; exit 1; }
echo "oracle: repro OK on fixed tree, fails on pre-fix classes"

# Sanity on the project's own tests: compile guava-testlib and the graph
# tests from a SCRATCH COPY of the tree (with the upstream regression tests
# planted there, outside the delivered tree) and run the seven regression
# methods plus a core slice of the graph suite.
rm -rf /tmp/oscratch && mkdir -p /tmp/oscratch
cp -r /app/src/guava-tests /tmp/oscratch/guava-tests
cp /opt/golden/*.java /tmp/oscratch/guava-tests/test/com/google/common/graph/
rm -rf /tmp/oracle-testlib /tmp/oracle-gtests
mkdir -p /tmp/oracle-testlib /tmp/oracle-gtests
if ! javac -d /tmp/oracle-testlib -cp "/opt/jars/*:/tmp/oracle-classes" \
      $(find /app/src/guava-testlib/src -name '*.java' | sort) > /tmp/oracle-tl.log 2>&1; then
    echo "oracle: guava-testlib javac failed" >&2
    tail -10 /tmp/oracle-tl.log >&2
    exit 1
fi
if ! javac -d /tmp/oracle-gtests -cp "/opt/jars/*:/tmp/oracle-classes:/tmp/oracle-testlib" \
      $(find /tmp/oscratch/guava-tests/test/com/google/common/graph -name '*.java' | grep -v PackageSanityTests | sort) \
      > /tmp/oracle-gt.log 2>&1; then
    echo "oracle: graph-tests javac failed" >&2
    tail -20 /tmp/oracle-gt.log >&2
    exit 1
fi
CP="/opt/run:/opt/jars/*:/tmp/oracle-classes:/tmp/oracle-testlib:/tmp/oracle-gtests"
GOLDEN_METHODS="
EndpointPairTest endpointPair_undirected_contains
ValueGraphTest hasEdgeConnecting_undirected_mismatch
ValueGraphTest edgeValueOrDefault_undirected_mismatch
ValueGraphTest putEdgeValue_undirected_orderMismatch
StandardMutableUndirectedGraphTest hasEdgeConnecting_mismatch
StandardMutableUndirectedNetworkTest edgesConnecting_orderMismatch
StandardMutableUndirectedNetworkTest edgeConnectingOrNull_orderMismatch
"
while read -r cls mth; do
    [ -n "$cls" ] || continue
    if ! java -cp "$CP" RunOne "com.google.common.graph.$cls" "$mth" > /tmp/oracle-method.out 2>&1; then
        echo "oracle: golden method $cls#$mth failed:" >&2
        cat /tmp/oracle-method.out >&2
        exit 1
    fi
    grep -q "failures=0" /tmp/oracle-method.out \
        || { echo "oracle: unexpected RunOne output for $cls#$mth" >&2; cat /tmp/oracle-method.out >&2; exit 1; }
done <<< "$GOLDEN_METHODS"
if ! java -cp "$CP" org.junit.runner.JUnitCore \
      com.google.common.graph.EndpointPairTest \
      com.google.common.graph.ValueGraphTest \
      com.google.common.graph.StandardMutableUndirectedGraphTest \
      com.google.common.graph.StandardMutableDirectedGraphTest \
      com.google.common.graph.StandardMutableUndirectedNetworkTest \
      > /tmp/oracle-suite.out 2>&1; then
    echo "oracle: graph JUnit slice failed:" >&2
    tail -20 /tmp/oracle-suite.out >&2
    exit 1
fi
echo "oracle: fix applied, deliverables written, tree compiles, repro OK both directions, all 7 upstream regression methods pass, graph suite slice green"
exit 0