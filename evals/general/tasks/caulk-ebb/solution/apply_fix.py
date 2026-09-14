#!/usr/bin/env python3
"""Apply the upstream fix to the networkx checkout at /app/src.

The bug (upstream issue #8726): geometric_soft_configuration_graph computes
the mean hidden degree from a kappas mapping by summing the mapping's KEYS
(`mean_degree = sum(kappas) / len(kappas)` in networkx/generators/geometric.py)
instead of its values.  With string node labels the call raises TypeError;
with integer node labels it silently uses the ids in place of the degrees.

The fix is the upstream one-line change:
    mean_degree = sum(kappas) / len(kappas)
becomes
    mean_degree = sum(kappas.values()) / len(kappas)

Fails loudly unless exactly one occurrence of the buggy line is replaced.
"""
import sys
from pathlib import Path

path = Path("/app/src/networkx/generators/geometric.py")
text = path.read_text()
buggy = "        mean_degree = sum(kappas) / len(kappas)"
fixed = "        mean_degree = sum(kappas.values()) / len(kappas)"
count = text.count(buggy)
if count != 1:
    print(f"error: expected exactly one occurrence of the buggy line, found {count}")
    sys.exit(1)
path.write_text(text.replace(buggy, fixed))
print("geometric.py fixed: mean hidden degree now computed from kappas.values()")