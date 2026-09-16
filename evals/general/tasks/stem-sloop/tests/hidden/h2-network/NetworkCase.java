import com.google.common.graph.EndpointPair;
import com.google.common.graph.NetworkBuilder;
import com.google.common.graph.MutableNetwork;
import java.util.Set;

/** Hidden case 2: undirected Network with explicit edge objects (AbstractNetwork code path). */
public final class NetworkCase {
  public static void main(String[] args) {
    MutableNetwork<Integer, String> n = NetworkBuilder.undirected().build();
    n.addEdge(10, 20, "e1");
    Set<EndpointPair<Integer>> edges = n.asGraph().edges();

    check(edges.size() == 1, "edges().size() must be 1");
    check(!edges.contains(EndpointPair.ordered(10, 20)),
        "network asGraph().edges() must not contain an ordered pair on an undirected network");
    check(edges.contains(EndpointPair.unordered(10, 20)),
        "network asGraph().edges() must contain the unordered pair");
    check(edges.contains(EndpointPair.unordered(20, 10)),
        "network asGraph().edges() must contain the reversed unordered pair (equal element)");
    int matching = 0;
    for (EndpointPair<Integer> e : edges) {
      if (e.equals(EndpointPair.ordered(10, 20))) matching++;
    }
    check(matching == 0, "no element of edges() may equal the ordered pair");

    throwsIAE("edgesConnecting(ordered pair)",
        () -> n.edgesConnecting(EndpointPair.ordered(10, 20)));
    throwsIAE("edgeConnecting(ordered pair)",
        () -> n.edgeConnecting(EndpointPair.ordered(10, 20)));
    throwsIAE("edgeConnectingOrNull(ordered pair)",
        () -> n.edgeConnectingOrNull(EndpointPair.ordered(10, 20)));

    check(n.edgesConnecting(EndpointPair.unordered(10, 20)).equals(java.util.Collections.singleton("e1")),
        "edgesConnecting(unordered) must return the edge");
    check("e1".equals(n.edgeConnectingOrNull(EndpointPair.unordered(10, 20))),
        "edgeConnectingOrNull(unordered) must return the edge");

    System.out.println("H2 OK");
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
    System.out.println("H2 FAIL: " + msg);
    System.exit(1);
  }
}