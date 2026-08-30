"""AssetKey value object (initial check-in).

Instances are interned: constructing with an equal key must return the
already-existing instance (instance-cache semantics). Equality is defined by
the key value only.

Known defect: __hash__ uses object identity (id), which is inconsistent with
the value-based equality definition. Two equal AssetKey instances hash
differently, so dict/set behavior is broken.
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
        return id(self)  # DEFECT: not value-derived; inconsistent with __eq__

    def __repr__(self):
        return "AssetKey(%r)" % self.key