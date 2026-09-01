#!/usr/bin/env bash
# Hidden case 4: hash must be value-derived and consistent with the equality
# definition across many values, and the instance cache must keep deduplicating
# by equality (never by memory identity).
set -u
python3 - <<'PY' || exit 1
import sys
sys.path.insert(0, "/app")
from value import AssetKey

# many distinct keys, produced through a couple of aliasing tricks
keys = ["unit:%d" % i for i in range(200)]
keys += ["area:alpha", "area:beta", "area:alpha", "node:y2k"]

seen_before = {}
for k in keys:
    obj = AssetKey(k)
    # every construction must honor the cache: creating the same key again
    # returns the SAME instance
    again = AssetKey(k)
    assert again is obj, "cache returned a different instance for %r" % k
    # value-derived hash
    assert hash(obj) == hash(k), "hash not derived from value for %r" % k
    # hash consistent with equality: two equal objects hash equally
    assert hash(obj) == hash(again)
    # kind buckets must never collide
    if k in seen_before:
        other = seen_before[k]
        assert other == obj and hash(other) == hash(obj)
    else:
        seen_before[k] = obj

# distinct values must not dedup into one instance and must not all share a hash
distinct = [AssetKey("sig-%d" % i) for i in range(50)]
instances = set()
hashes = set()
for o in distinct:
    instances.add(id(o))
    hashes.add(hash(o))
assert len(instances) == len(distinct), "distinct values collapsed to one instance"
assert len(hashes) > 40, "distinct values produced colliding hashes"

# dict behavior across the whole family
m = {AssetKey("k-%d" % i): i for i in range(100)}
for i in range(100):
    assert m[AssetKey("k-%d" % i)] == i, "dict lookup broken at %d" % i

print("VALUE-EDGE-OK")
PY
echo "hidden-value-edge: passed"
exit 0