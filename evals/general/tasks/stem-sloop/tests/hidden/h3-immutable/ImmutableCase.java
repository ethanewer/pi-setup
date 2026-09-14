import com.google.common.graph.EndpointPair;
import com.google.common.graph.GraphBuilder;
import com.google.common.graph.ImmutableGraph;
import java.util.Set;

/** Hidden case 3: ImmutableGraph path plus a directed-graph regression check. */
public final class ImmutableCase {
  public static void main(String[] args) {
    ImmutableGraph<Integer> g =
        GraphBuilder.undirected().<Integer>immutable().putEdge(7, 9).build();
    Set<EndpointPair<Integer>> edges = g.edges();

    check(edges.size() == 1, "edges().size() must be 1");
    check(!edges.contains(EndpointPair.ordered(7, 9)),
        "immutable undirected edges() must not contain an ordered pair");
    check(edges.contains(EndpointPair.unordered(7, 9)),
        "immutable undirected edges() must contain the unordered pair");
    int matching = 0;
    for (EndpointPair<Integer> e : edges) {
      if (e.equals(EndpointPair.ordered(7, 9))) matching++;
    }
    check(matching == 0, "no element of edges() may equal the ordered pair");
    check(!g.hasEdgeConnecting(EndpointPair.ordered(7, 9)),
        "immutable hasEdgeConnecting(ordered) must report false");
    check(g.hasEdgeConnecting(EndpointPair.unordered(7, 9)),
        "immutable hasEdgeConnecting(unordered) must report true");

    // Directed behaviour must be untouched by the fix: ordered pairs accepted,
    // unordered pairs rejected.
    ImmutableGraph<Integer> d =
        GraphBuilder.directed().<Integer>immutable().putEdge(5, 6).build();
    Set<EndpointPair<Integer>> dedges = d.edges();
    check(dedges.contains(EndpointPair.ordered(5, 6)),
        "directed edges() must contain the ordered pair");
    check(!dedges.contains(EndpointPair.unordered(5, 6)),
        "directed edges() must not contain an unordered pair");
    check(d.hasEdgeConnecting(EndpointPair.ordered(5, 6)),
        "directed hasEdgeConnecting(ordered) must report true");
    check(!d.hasEdgeConnecting(EndpointPair.unordered(5, 6)),
        "directed hasEdgeConnecting(unordered) must report false");

    System.out.println("H3 OK");
  }

  private static void check(boolean b, String msg) {
    if (!b) {
      System.out.println("H3 FAIL: " + msg);
      System.exit(1);
    }
  }
}