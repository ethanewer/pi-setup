"""Hidden case: delattr of an attribute that cannot be removed from an object.

The upstream regression test uses a slot class attribute (`__slots__ = ()`).
This case uses a different failure input: a property that has no deleter.
A failing delattr must register nothing to undo, so undo() stays a no-op and
rolls back exactly the successful mutations that followed.
"""

import pytest


def test_failed_delattr_readonly_property_undo_is_noop(monkeypatch):
    class Record:
        @property
        def name(self):
            return "readonly"

    rec = Record()
    with pytest.raises(AttributeError):
        monkeypatch.delattr(rec, "name")
    assert rec.name == "readonly"
    monkeypatch.undo()  # must not raise


def test_failed_delattr_then_successful_setattr_undo(monkeypatch):
    class Record:
        def __init__(self):
            self.value = 1

        @property
        def name(self):
            return "readonly"

    rec = Record()
    with pytest.raises(AttributeError):
        monkeypatch.delattr(rec, "name")  # fails: property without a deleter
    monkeypatch.setattr(rec, "value", 2)  # succeeds
    monkeypatch.undo()
    # Only the successful setattr is rolled back; the failed delattr must
    # contribute nothing on top of that (no stale entry, no re-raised error).
    assert rec.value == 1
    assert rec.name == "readonly"