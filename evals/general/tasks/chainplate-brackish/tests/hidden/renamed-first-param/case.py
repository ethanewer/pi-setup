"""Renamed first method parameter: this.__class__ is the same spelling as
type(this) and must be just as accepted."""


class Store:
    _items = []

    def read_own(this):
        """Access through this.__class__ is equivalent to type(this)."""
        if this.__class__._items is None:
            return this.__class__._items
        return None

    def read_foreign(this, other):
        """Access through another object's class keeps warning."""
        return other.__class__._items  # [protected-access]