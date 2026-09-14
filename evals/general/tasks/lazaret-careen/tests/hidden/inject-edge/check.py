#!/usr/bin/env python3
"""Hidden case for lazaret-careen: quote + GML `edge` fragment injection in
the SECOND element of a 3-tuple node label.

The upstream regression test puts its injection in the first element of a
2-tuple; this case exercises the same tuple-label escape path from a
different shape: a 3-tuple whose second element carries `"] edge [`, which
on the unfixed parent tree breaks GML parsing entirely (NetworkXError
"cannot tokenize ...") — and on a fixed tree must round-trip as exactly one
node with the label intact. It also asserts the label's own double-quote
character survives the round-trip.
"""
import networkx as nx

CASE = "inject-edge"

label = ('a', 'b"] edge [ id 7 source 1 target 2', 'c')
G = nx.Graph()
G.add_node(label)

data = "\n".join(nx.generate_gml(G))

# The quote inside the tuple label must be escaped to the &#34; entity …
assert "&#34;" in data, f"{CASE}: tuple label double quote was not escaped to &#34;"
# … and the raw quote + GML fragment must never appear in the emitted text.
assert '"] edge [' not in data, f"{CASE}: raw quote closes the GML string early (injection)"

H = nx.parse_gml(data)
assert len(H) == 1, f"{CASE}: round-trip produced {len(H)} nodes instead of 1"

expected = "(" + ",".join(repr(v) for v in label) + ")"
assert list(H) == [expected], f"{CASE}: label round-tripped to {list(H)!r}, want {[expected]!r}"

print(f"OK {CASE}: 3-tuple label with quote+edge injection round-trips as one node")