#!/usr/bin/env python3
"""Hidden case for lazaret-careen: mixed-type tuple node label whose repr
contains BOTH a backslash and a double quote — escaping must not corrupt
the round-trip of the other repr characters.

Upstream's regression test uses only string elements; this case makes the
second element a non-string (int) and the third a float, and puts the
tricky characters (backslash before quote) in the first element. On the
unfixed parent tree the raw quote breaks parsing (NetworkXError); on a
fixed tree the generated GML must carry the escaped entity while the
BACKSLASH itself remains verbatim, and the round-trip must reproduce the
exact label text.
"""
import networkx as nx

CASE = "backslash-mixed"

label = ('a\\"b', 1, 2.5)
G = nx.Graph()
G.add_node(label)

data = "\n".join(nx.generate_gml(G))

# escape() must encode the double quote as an entity — and must NOT mangle
# the backslash (a legal GML character that repr doubles but that must stay
# verbatim in the file). The emitted text is the repr of the element with
# only the double quote replaced by the entity.
assert "&#34;" in data, f"{CASE}: tuple label double quote was not escaped to &#34;"
assert '\\"b' not in data, f"{CASE}: raw quote remains in GML output (injection)"
assert repr(label[0]).replace('"', "&#34;") in data, f"{CASE}: label text mangled"

H = nx.parse_gml(data)
assert len(H) == 1, f"{CASE}: round-trip produced {len(H)} nodes instead of 1"

expected = "(" + ",".join(repr(v) for v in label) + ")"
assert list(H) == [expected], f"{CASE}: label round-tripped to {list(H)!r}, want {[expected]!r}"

print(f"OK {CASE}: mixed-type tuple label with backslash+quote round-trips as one node")