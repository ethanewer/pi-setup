"""Safe YAML configuration overlays."""

from __future__ import annotations

from collections.abc import Mapping

from . import load as _load
from .loader import SafeLoader
from .nodes import ScalarNode


class _Delete:
    __slots__ = ()

    def __repr__(self):
        return "DELETE"


DELETE = _Delete()


class _OverlayLoader(SafeLoader):
    pass


def _construct_delete(loader, node):
    if not isinstance(node, ScalarNode):
        raise ValueError("!delete must be used on a scalar")
    # The scalar spelling is intentionally immaterial: the tag is the marker.
    return DELETE


_OverlayLoader.add_constructor("!delete", _construct_delete)


def load_overlay(stream):
    """Load one YAML mapping using safe construction and overlay semantics."""
    try:
        value = _load(stream, Loader=_OverlayLoader)
    except Exception as exc:
        if isinstance(exc, (TypeError, ValueError)):
            raise
        raise ValueError("invalid overlay YAML: %s" % exc) from exc
    if not isinstance(value, Mapping):
        raise ValueError("overlay document root must be a mapping")
    _assert_acyclic(value)
    _validate_tree(value, in_mapping_value=False)
    return value


def _assert_acyclic(value, active=None, done=None):
    if not isinstance(value, (Mapping, list, tuple)):
        return
    if active is None:
        active, done = set(), set()
    ident = id(value)
    if ident in active:
        raise ValueError("cyclic YAML alias/object graph")
    if ident in done:
        return
    active.add(ident)
    if isinstance(value, Mapping):
        for key, item in value.items():
            _assert_acyclic(key, active, done)
            _assert_acyclic(item, active, done)
    else:
        for item in value:
            _assert_acyclic(item, active, done)
    active.remove(ident)
    done.add(ident)


def _validate_tree(value, *, in_mapping_value):
    """Validate marker placement and reject marker keys in a copied tree."""
    if value is DELETE:
        if not in_mapping_value:
            raise ValueError("DELETE is only valid as a mapping value")
        return
    if isinstance(value, Mapping):
        for key, item in value.items():
            if key is DELETE:
                raise ValueError("DELETE cannot be used as a mapping key")
            _validate_tree(key, in_mapping_value=False)
            _validate_tree(item, in_mapping_value=True)
    elif isinstance(value, (list, tuple)):
        for item in value:
            if item is DELETE:
                raise ValueError("DELETE cannot be used directly inside a sequence")
            _validate_tree(item, in_mapping_value=False)


def _copy_tree(value, active=None):
    """Copy a tree, dropping DELETE entries from mappings."""
    if value is DELETE:
        return DELETE
    if not isinstance(value, (Mapping, list, tuple)):
        return value
    if active is None:
        active = set()
    ident = id(value)
    if ident in active:
        raise ValueError("cyclic YAML alias/object graph")
    active.add(ident)
    try:
        if isinstance(value, Mapping):
            result = {}
            for key, item in value.items():
                if key is DELETE:
                    raise ValueError("DELETE cannot be used as a mapping key")
                copied_key = _copy_tree(key, active)
                if item is DELETE:
                    continue
                result[copied_key] = _copy_tree(item, active)
            return result
        if isinstance(value, list):
            result = []
            for item in value:
                if item is DELETE:
                    raise ValueError("DELETE cannot be used directly inside a sequence")
                result.append(_copy_tree(item, active))
            return result
        result = []
        for item in value:
            if item is DELETE:
                raise ValueError("DELETE cannot be used directly inside a sequence")
            result.append(_copy_tree(item, active))
        return tuple(result)
    finally:
        active.remove(ident)


def _merge_mapping(base, overlay, list_mode):
    if not isinstance(base, Mapping):
        raise TypeError("overlay mapping requires a mapping base")
    result = _copy_tree(base)
    for key, over_value in overlay.items():
        if key is DELETE:
            raise ValueError("DELETE cannot be used as a mapping key")
        if over_value is DELETE:
            result.pop(key, None)
            continue
        if key not in base:
            result[_copy_tree(key)] = _copy_tree(over_value)
            continue
        base_value = base[key]
        if isinstance(over_value, Mapping):
            if not isinstance(base_value, Mapping):
                raise TypeError("overlay mapping requires a mapping base")
            result[key] = _merge_mapping(base_value, over_value, list_mode)
        elif isinstance(over_value, list):
            if not isinstance(base_value, list):
                raise TypeError("overlay list requires a list base")
            copied_overlay = _copy_tree(over_value)
            if list_mode == "replace":
                result[key] = copied_overlay
            elif list_mode == "append":
                result[key] = _copy_tree(base_value) + copied_overlay
            else:
                merged = _copy_tree(base_value)
                for item in copied_overlay:
                    if item not in merged:
                        merged.append(item)
                result[key] = merged
        else:
            result[key] = _copy_tree(over_value)
    return result


def apply_overlay(base, overlay, *, list_mode="replace"):
    """Return a copied mapping with *overlay* applied to *base*."""
    if list_mode not in {"replace", "append", "unique"}:
        raise ValueError("unknown list mode: %r" % (list_mode,))
    if not isinstance(base, Mapping):
        raise TypeError("base must be a mapping")
    if not isinstance(overlay, Mapping):
        raise TypeError("overlay must be a mapping")
    _assert_acyclic(base)
    _assert_acyclic(overlay)
    _validate_tree(overlay, in_mapping_value=False)
    return _merge_mapping(base, overlay, list_mode)
