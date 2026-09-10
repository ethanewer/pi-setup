"""runtime.registry — the JSON-schema tool registry and its canonical validator.

validate(name, args) -> Optional[str]
    Returns None when the call is schema-valid, otherwise a canonical
    `SCHEMA_ERROR:<tool>:<path>:<constraint>:<value>` string.  Exactly one
    error is reported per call: the first failing parameter in declaration
    order, and within a parameter the first failing rule in the order
    required -> type -> minimum -> maximum -> maxLength -> minItems -> items.
    deterministically, so two correct executors always see the same string.
"""
from __future__ import annotations

import json
import os
from pathlib import Path

DEFAULT_REGISTRY_PATH = os.environ.get("FLUME_REGISTRY_PATH", "/app/registry.json")


class ToolRegistry:
    def __init__(self, path=None):
        path = Path(path or DEFAULT_REGISTRY_PATH)
        self._raw = json.loads(path.read_text())
        self._tools = {t["name"]: t for t in self._raw["tools"]}
        self._order = [t["name"] for t in self._raw["tools"]]

    def names(self):
        return list(self._order)

    def is_idempotent(self, name):
        return bool(self._tools[name].get("idempotent"))

    def validate(self, name, args):
        tool = self._tools[name]
        params = tool["parameters"]
        props = params.get("properties", {})
        required = params.get("required", [])

        for key in required:
            if key not in args:
                return "SCHEMA_ERROR:%s:%s:required:missing" % (name, key)

        for key, schema in props.items():
            if key not in args:
                continue
            value = args[key]
            typ = schema.get("type")
            if typ and not self._type_ok(typ, value):
                return "SCHEMA_ERROR:%s:%s:type:%s" % (name, key, typ)
            if isinstance(value, bool):
                continue
            if "minimum" in schema and value < schema["minimum"]:
                return "SCHEMA_ERROR:%s:%s:minimum:%s" % (name, key, schema["minimum"])
            if "maximum" in schema and value > schema["maximum"]:
                return "SCHEMA_ERROR:%s:%s:maximum:%s" % (name, key, schema["maximum"])
            if "maxLength" in schema and len(value) > schema["maxLength"]:
                return "SCHEMA_ERROR:%s:%s:maxLength:%s" % (name, key, schema["maxLength"])
            if "minItems" in schema and len(value) < schema["minItems"]:
                return "SCHEMA_ERROR:%s:%s:minItems:%s" % (name, key, schema["minItems"])
            if "items" in schema:
                item_type = schema["items"].get("type")
                for item in value:
                    if item_type and not self._type_ok(item_type, item):
                        return "SCHEMA_ERROR:%s:%s:itemsType:%s" % (name, key, item_type)
        return None

    @staticmethod
    def _type_ok(typ, value):
        if typ == "string":
            return isinstance(value, str)
        if typ == "integer":
            return isinstance(value, int) and not isinstance(value, bool)
        if typ == "number":
            return isinstance(value, (int, float)) and not isinstance(value, bool)
        if typ == "boolean":
            return isinstance(value, bool)
        if typ == "array":
            return isinstance(value, (list, tuple))
        return True