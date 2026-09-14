"""Hidden case: interleaving of failed and successful mutations on the SAME
monkeypatch, in both orderings. undo() must roll back exactly and only the
operations that succeeded and skip the failed one — never re-raising the
failed operation's exception and never rolling back a change that did not
happen. The upstream regression test does not mix outcomes on one patch.
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


def test_failed_then_successful_then_undo(monkeypatch):
    mapping = GuardedDict(sealed=0, a=1, b=2)
    with pytest.raises(TypeError):
        monkeypatch.setitem(mapping, "sealed", 999)  # fails: records nothing
    monkeypatch.setitem(mapping, "a", 100)  # succeeds
    monkeypatch.delitem(mapping, "b")  # succeeds
    monkeypatch.undo()
    assert mapping == {"sealed": 0, "a": 1, "b": 2}


def test_successful_then_failed_then_undo(monkeypatch):
    mapping = GuardedDict(sealed=0, a=1)
    monkeypatch.setitem(mapping, "a", 100)  # succeeds
    with pytest.raises(TypeError):
        monkeypatch.delitem(mapping, "sealed")  # fails: records nothing
    monkeypatch.undo()
    assert mapping == {"sealed": 0, "a": 1}


def test_failed_setitem_then_failed_delitem_then_undo(monkeypatch):
    mapping = GuardedDict(sealed=0)
    with pytest.raises(TypeError):
        monkeypatch.setitem(mapping, "sealed", 1)  # fails
    with pytest.raises(TypeError):
        monkeypatch.delitem(mapping, "sealed")  # fails
    monkeypatch.undo()  # nothing succeeded: must be a no-op
    assert mapping == {"sealed": 0}