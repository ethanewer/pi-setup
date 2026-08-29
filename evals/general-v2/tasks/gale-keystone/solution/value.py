"""AssetKey value object (fixed).

Instance-cache semantics and the equality definition are preserved from the
original check-in. The hash is now value-derived so it is consistent with
__eq__: equal keys hash equal, and hashing an AssetKey equals hashing its
raw key value.
"""

class AssetKey:
    _registry = []

    def __new__(cls, key: str):
        obj = super().__new__(cls)
        obj.key = key
        for inst in cls._registry:
            if inst == obj:
                return inst
        cls._registry.append(obj)
        return obj

    def __eq__(self, other):
        if not isinstance(other, AssetKey):
            return NotImplemented
        return self.key == other.key

    def __hash__(self):
        return hash(self.key)

    def __repr__(self):
        return "AssetKey(%r)" % self.key


def _selfcheck():
    a = AssetKey("dup:owl-1")
    b = AssetKey("dup:owl-1")  # must return the cached instance
    c = AssetKey("other:x2")
    assert a == b, "equality"
    assert a is b, "instance-cache dedup by equality"
    assert hash(a) == hash(b), "hash consistent with equality"
    assert hash(a) == hash("dup:owl-1"), "hash derived from value"
    assert a != c and a is not c, "distinct values distinct instances"
    assert isinstance(hash(a), int), "int hash"
    sample = {}
    sample[a] = "yes"
    assert sample[b] == "yes", "dict lookup through equal key"
    print("VALUE-SELFCHECK-OK")
    print("equality ok; cache-dedup ok; value-derived-hash ok")


if __name__ == "__main__":
    _selfcheck()