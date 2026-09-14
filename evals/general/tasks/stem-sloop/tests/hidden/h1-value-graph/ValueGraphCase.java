import com.google.common.graph.EndpointPair;
import com.google.common.graph.ValueGraphBuilder;
import com.google.common.graph.MutableValueGraph;
import java.util.Set;

/** Hidden case 1: undirected ValueGraph with String nodes and Long values. */
public final class ValueGraphCase {
  public static void main(String[] args) {
    MutableValueGraph<String, Long> g = ValueGraphBuilder.undirected().build();
    g.putEdgeValue("alpha", "beta", 7L);
    Set<EndpointPair<String>> edges = g.edges();

    check(edges.size() == 1, "edges().size() must be 1");
    check(!edges.contains(EndpointPair.ordered("alpha", "beta")),
        "edges() must not contain an ordered pair on an undirected graph");
    check(edges.contains(EndpointPair.unordered("alpha", "beta")),
        "edges() must contain the unordered pair");
    check(edges.contains(EndpointPair.unordered("beta", "alpha")),
        "edges() must contain the reversed unordered pair (equal element)");
    int matching = 0;
    for (EndpointPair<String> e : edges) {
      if (e.equals(EndpointPair.ordered("alpha", "beta"))) matching++;
    }
    check(matching == 0, "no element of edges() may equal the ordered pair");

    check(!g.hasEdgeConnecting(EndpointPair.ordered("alpha", "beta")),
        "hasEdgeConnecting(ordered) must report false, not a false positive");
    check(g.hasEdgeConnecting(EndpointPair.unordered("alpha", "beta")),
        "hasEdgeConnecting(unordered) must report true");

    throwsIAE("putEdgeValue(ordered pair)",
        () -> g.putEdgeValue(EndpointPair.ordered("alpha", "beta"), 9L));
    throwsIAE("edgeValueOrDefault(ordered pair)",
        () -> g.edgeValueOrDefault(EndpointPair.ordered("alpha", "beta"), -1L));

    System.out.println("H1 OK");
  }

  private static void throwsIAE(String what, Runnable r) {
    try {
      r.run();
      fail(what + " must throw IllegalArgumentException");
    } catch (IllegalArgumentException expected) {
      // good
    }
  }

  private static void check(boolean b, String msg) {
    if (!b) fail(msg);
  }

  private static void fail(String msg) {
    System.out.println("H1 FAIL: " + msg);
    System.exit(1);
  }
}