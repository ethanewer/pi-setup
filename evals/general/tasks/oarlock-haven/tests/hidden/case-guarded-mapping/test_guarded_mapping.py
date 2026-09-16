"""Hidden case: setitem/delitem failures on a MUTABLE mapping subclass that
refuses certain keys, instead of the immutable mapping proxy the upstream
regression test uses. A failed mutation must register nothing to undo, so the
subsequent undo() is a no-op.

GuardedDict has normal (mutable) dict semantics for every key except 'sealed',
which raises TypeError on both __setitem__ and __delitem__ — so the failure is
raised by the mapping itself, not merely by its immutability.
"""

import pytest


class GuardedDict(dict):
    def __setitem__(self, key, value):
        if key == "sealed":
            raise TypeError(f"key {key!r} is sealed")
        super().__setitem__(key, value)

    def __delitem__(self, key):
        if key == "sealed":
            raise TypeError(f"key {key!r} is sealed")
        super().__delitem__(key)


def test_failed_setitem_guarded_key_undo_is_noop(monkeypatch):
    mapping = GuardedDict(sealed=0, open_=1)
    with pytest.raises(TypeError):
        monkeypatch.setitem(mapping, "sealed", 999)
    assert mapping["sealed"] == 0
    monkeypatch.undo()  # must not raise


def test_failed_delitem_guarded_key_undo_is_noop(monkeypatch):
    mapping = GuardedDict(sealed=0, open_=1)
    with pytest.raises(TypeError):
        monkeypatch.delitem(mapping, "sealed")
    assert mapping["sealed"] == 0
    monkeypatch.undo()  # must not raise