#!/usr/bin/env python3
"""Hidden case for lazaret-careen: quote + GML `node` fragment injection in
the SECOND element of a 2-tuple node label, verified through the FILE API.

On the unfixed parent tree the raw quote closes the label string early and
the `"] node [ id 55 label "inject` fragment is parsed as a real second
node, so writing the graph and reading it back yields TWO nodes
(["('x','y", "inject')"]) instead of the one that was written. The fixed
tree must escape the quote (&#34;), emit no raw `"] node [` fragment, and
write_gml/read_gml must round-trip the exact single labelled node.
"""
import os
import tempfile

import networkx as nx

CASE = "inject-node"

label = ('x', 'y"] node [ id 55 label "inject')
G = nx.Graph()
G.add_node(label)

data = "\n".join(nx.generate_gml(G))

assert "&#34;" in data, f"{CASE}: tuple label double quote was not escaped to &#34;"
assert '"] node [' not in data, f"{CASE}: raw quote closes the GML string early (node injection)"

H = nx.parse_gml(data)
assert len(H) == 1, f"{CASE}: parse round-trip produced {len(H)} nodes instead of 1"

# Same path through the file API: write_gml then read_gml must round-trip
# the graph, and the single node must carry the full label text including
# the embedded double quote.
fd, path = tempfile.mkstemp(suffix=".gml")
os.close(fd)
try:
    nx.write_gml(G, path)
    with open(path, encoding="utf-8") as fh:
        filedata = fh.read()
    assert "&#34;" in filedata, f"{CASE}: write_gml did not escape the label quote"
    assert '"] node [' not in filedata, f"{CASE}: write_gml emitted a raw quote (injection)"
    H2 = nx.read_gml(path)
    assert len(H2) == 1, f"{CASE}: file round-trip produced {len(H2)} nodes instead of 1"
    expected = "(" + ",".join(repr(v) for v in label) + ")"
    assert list(H2) == [expected], f"{CASE}: file round-trip label is {list(H2)!r}, want {[expected]!r}"
finally:
    os.unlink(path)

print(f"OK {CASE}: quote+node injection round-trips as one node through write_gml/read_gml")