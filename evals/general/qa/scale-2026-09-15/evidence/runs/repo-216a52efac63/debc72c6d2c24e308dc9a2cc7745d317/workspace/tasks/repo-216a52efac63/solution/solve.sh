#!/bin/sh
set -eu
python3 - <<'PY'
from pathlib import Path

path = Path("/app/jinja/src/jinja2/filters.py")
text = path.read_text()
replacements = {
    "from .utils import htmlsafe_json_dumps\n": "from .utils import htmlsafe_json_dumps\nfrom .utils import missing\n",
    "    default: t.Any | None = None,\n": "    default: t.Any = missing,\n",
    "            if default is not None and isinstance(item, Undefined):\n": "            if default is not missing and isinstance(item, Undefined):\n",
    '        default = kwargs.pop("default", None)\n': '        default = kwargs.pop("default", missing)\n',
    "    )\n    out = [\n        _GroupTuple(key, list(values))\n        for key, values in groupby(sorted(value, key=expr), expr)\n": "    )\n\n    def sort_key(item: V) -> tuple[bool, t.Any]:\n        key = expr(item)\n        return key is not None, key if key is not None else \"\"\n\n    out = [\n        _GroupTuple(key, list(values))\n        for key, values in groupby(sorted(value, key=sort_key), expr)\n",
    "    )\n    out = [\n        _GroupTuple(key, await auto_to_list(values))\n        for key, values in groupby(sorted(await auto_to_list(value), key=expr), expr)\n": "    )\n\n    def sort_key(item: V) -> tuple[bool, t.Any]:\n        key = expr(item)\n        return key is not None, key if key is not None else \"\"\n\n    out = [\n        _GroupTuple(key, await auto_to_list(values))\n        for key, values in groupby(sorted(await auto_to_list(value), key=sort_key), expr)\n",
}
for old, new in replacements.items():
    if old not in text:
        raise SystemExit(f"oracle could not find expected source fragment: {old!r}")
    text = text.replace(old, new, 3 if "default: t.Any | None" in old else 1)
path.write_text(text)
PY
