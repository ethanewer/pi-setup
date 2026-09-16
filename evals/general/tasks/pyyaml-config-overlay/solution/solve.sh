#!/bin/sh
set -eu
mkdir -p /app/pyyaml/lib/yaml
cat > /app/pyyaml/lib/yaml/config_overlay.py <<'PY'
"""Safe recursive overlays for YAML configuration mappings."""

import collections.abc
import yaml
from yaml.constructor import ConstructorError
from yaml.nodes import ScalarNode


class _Delete:
    def __repr__(self):
        return "DELETE"


DELETE = _Delete()


class _OverlayLoader(yaml.SafeLoader):
    pass


def _construct_delete(loader, node):
    if not isinstance(node, ScalarNode):
        raise ConstructorError(None, None, "!delete must tag a scalar", node.start_mark)
    if loader.construct_scalar(node) not in ("", "null"):
        raise ConstructorError(None, None, "!delete value must be empty or null", node.start_mark)
    return DELETE


_OverlayLoader.add_constructor("!delete", _construct_delete)


def load_overlay(stream):
    """Safely load one mapping document, including the !delete marker."""
    value = yaml.load(stream, Loader=_OverlayLoader)
    if not isinstance(value, collections.abc.Mapping):
        raise ValueError("overlay document must have a mapping root")
    return value


def _ensure_acyclic(value, active=None):
    if active is None:
        active = set()
    if isinstance(value, (collections.abc.Mapping, list, tuple)):
        marker = id(value)
        if marker in active:
            raise ValueError("cyclic mapping or sequence is not supported")
        active.add(marker)
        try:
            if isinstance(value, collections.abc.Mapping):
                for key, item in value.items():
                    _ensure_acyclic(key, active)
                    _ensure_acyclic(item, active)
            else:
                for item in value:
                    _ensure_acyclic(item, active)
        finally:
            active.remove(marker)


def _copy(value):
    if value is DELETE:
        raise ValueError("DELETE cannot occur in a copied value")
    if isinstance(value, collections.abc.Mapping):
        result = {}
        for key, item in value.items():
            if key is DELETE:
                raise ValueError("DELETE cannot be a mapping key")
            result[_copy(key)] = _copy(item)
        return result
    if isinstance(value, list):
        return [_copy(item) for item in value]
    if isinstance(value, tuple):
        return tuple(_copy(item) for item in value)
    return value


def _materialize(value, path):
    if value is DELETE:
        raise ValueError("DELETE is not valid directly inside a sequence at " + path)
    if isinstance(value, collections.abc.Mapping):
        result = {}
        for key, item in value.items():
            if key is DELETE:
                raise ValueError("DELETE cannot be a mapping key at " + path)
            if item is DELETE:
                continue
            result[_copy(key)] = _materialize(item, path + "." + str(key))
        return result
    if isinstance(value, list):
        return [_materialize(item, path + "[]") for item in value]
    if isinstance(value, tuple):
        return tuple(_materialize(item, path + "()") for item in value)
    return value


def _merge(base, overlay, list_mode, path):
    if overlay is DELETE:
        raise ValueError("!delete is only valid as a mapping value at " + path)
    if isinstance(overlay, collections.abc.Mapping):
        if not isinstance(base, collections.abc.Mapping):
            raise TypeError("mapping overlay requires a mapping base at " + path)
        result = {}
        for key, value in base.items():
            if key is DELETE:
                raise ValueError("DELETE cannot be a mapping key at " + path)
            result[_copy(key)] = _copy(value)
        for key, value in overlay.items():
            if key is DELETE:
                raise ValueError("DELETE cannot be a mapping key at " + path)
            child_path = path + "." + str(key)
            if value is DELETE:
                result.pop(key, None)
            elif key in result:
                result[key] = _merge(result[key], value, list_mode, child_path)
            elif isinstance(value, collections.abc.Mapping):
                result[key] = _merge({}, value, list_mode, child_path)
            elif isinstance(value, (list, tuple)):
                result[key] = _materialize(value, child_path)
            else:
                result[key] = _copy(value)
        return result
    if isinstance(overlay, list):
        if not isinstance(base, list):
            raise TypeError("list overlay requires a list base at " + path)
        if list_mode == "replace":
            return _materialize(overlay, path)
        if list_mode == "append":
            return _copy(base) + _materialize(overlay, path)
        result = _copy(base)
        for item in overlay:
            copied = _materialize(item, path + "[]")
            if copied not in result:
                result.append(copied)
        return result
    if isinstance(overlay, tuple):
        return _materialize(overlay, path)
    return _copy(overlay)


def apply_overlay(base, overlay, *, list_mode="replace"):
    """Return a non-mutating recursive overlay of two configuration mappings."""
    if list_mode not in ("replace", "append", "unique"):
        raise ValueError("list_mode must be replace, append, or unique")
    if not isinstance(base, collections.abc.Mapping):
        raise TypeError("base must be a mapping")
    if not isinstance(overlay, collections.abc.Mapping):
        raise TypeError("overlay must be a mapping")
    _ensure_acyclic(base)
    _ensure_acyclic(overlay)
    return _merge(base, overlay, list_mode, "<root>")
PY
cat > /app/reproduce_overlay.py <<'PY'
#!/usr/bin/env python3
import argparse
import sys
from pathlib import Path

import yaml
from yaml.config_overlay import apply_overlay, load_overlay


def main():
    parser = argparse.ArgumentParser(description="apply a safe YAML config overlay")
    parser.add_argument("base")
    parser.add_argument("overlay")
    parser.add_argument("output")
    parser.add_argument("--list-mode", choices=("replace", "append", "unique"), default="replace")
    args = parser.parse_args()
    try:
        with Path(args.base).open(encoding="utf-8") as stream:
            base = yaml.safe_load(stream)
        with Path(args.overlay).open(encoding="utf-8") as stream:
            overlay = load_overlay(stream)
        result = apply_overlay(base, overlay, list_mode=args.list_mode)
        with Path(args.output).open("w", encoding="utf-8") as stream:
            yaml.safe_dump(result, stream, sort_keys=False)
    except (OSError, TypeError, ValueError, yaml.YAMLError) as exc:
        print("config overlay: %s" % exc, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY
chmod +x /app/reproduce_overlay.py
