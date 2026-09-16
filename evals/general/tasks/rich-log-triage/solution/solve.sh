#!/bin/sh
set -eu
cat > /app/triage.py <<'PY'
#!/usr/bin/env python3
import argparse
import json
import re
import sys
from collections import Counter
from datetime import datetime
from io import StringIO
from pathlib import Path

from rich.console import Console
from rich.text import Text

LEVELS = ("CRITICAL", "ERROR", "WARNING", "INFO", "DEBUG")
LEVEL_SET = set(LEVELS)
STAMP = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
REQUIRED = {"id", "timestamp", "level", "component", "message"}


def _has_control(value):
    return any(ord(ch) < 0x20 or 0x7F <= ord(ch) <= 0x9F for ch in value)


def _clean(value, name, position):
    if not isinstance(value, str) or not value or _has_control(value):
        raise ValueError(f"record {position}: invalid {name}")
    return value


def _parse(lines):
    records = []
    seen = set()
    for position, raw in enumerate(lines):
        if not isinstance(raw, str) or not raw.strip():
            raise ValueError(f"record {position}: blank line")
        try:
            item = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise ValueError(f"record {position}: invalid JSON") from exc
        if not isinstance(item, dict) or set(item) - (REQUIRED | {"tags"}) != set() or not REQUIRED <= set(item):
            raise ValueError(f"record {position}: invalid fields")
        ident = _clean(item["id"], "id", position)
        if ident in seen:
            raise ValueError(f"record {position}: duplicate id")
        seen.add(ident)
        stamp = _clean(item["timestamp"], "timestamp", position)
        if not STAMP.fullmatch(stamp):
            raise ValueError(f"record {position}: invalid timestamp")
        try:
            parsed_time = datetime.strptime(stamp, "%Y-%m-%dT%H:%M:%SZ")
        except ValueError as exc:
            raise ValueError(f"record {position}: invalid timestamp") from exc
        level = _clean(item["level"], "level", position)
        if level not in LEVEL_SET:
            raise ValueError(f"record {position}: invalid level")
        component = _clean(item["component"], "component", position)
        message = _clean(item["message"], "message", position)
        if "tags" in item:
            tags = item["tags"]
            if not isinstance(tags, list) or not tags or any(not isinstance(tag, str) or not tag or _has_control(tag) for tag in tags):
                raise ValueError(f"record {position}: invalid tags")
        records.append({"id": ident, "timestamp": stamp, "parsed": parsed_time, "level": level,
                        "component": component, "message": message, "position": position})
    return sorted(records, key=lambda record: (record["parsed"], record["position"]))


def _plain(text):
    stream = StringIO()
    console = Console(file=stream, force_terminal=False, color_system=None,
                      width=100000, markup=False, highlight=False, emoji=False)
    console.print(Text(text), end="")
    return stream.getvalue()


def build_report(lines):
    records = _parse(lines)
    counts = Counter(record["level"] for record in records)
    component_counts = Counter(record["component"] for record in records)
    first = {}
    for index, record in enumerate(records):
        first.setdefault(record["component"], index)
    components = sorted(component_counts, key=lambda name: (-component_counts[name], first[name], name))
    component_text = ", ".join(f"{name}={component_counts[name]}" for name in components) or "none=0"
    rows = ["Log triage report", f"Records: {len(records)}",
            "Levels: " + ", ".join(f"{level}={counts[level]}" for level in LEVELS),
            f"Components: {component_text}", "Events:"]
    rows.extend(f"[{record['timestamp']}] {record['level']} {record['component']}: {record['message']}" for record in records)
    return _plain("\n".join(rows) + "\n")


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)
    try:
        with open(args.input, encoding="utf-8", newline="") as source:
            report = build_report(source)
        Path(args.output).write_text(report, encoding="utf-8", newline="")
    except (OSError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY
cat > /app/repro_case.py <<'PY'
#!/usr/bin/env python3
from pathlib import Path
import sys

sys.path.insert(0, "/app")
from triage import build_report


def main():
    with Path("/app/source/events.jsonl").open(encoding="utf-8") as stream:
        report = build_report(stream)
    assert "Records: 4" in report
    assert "bad [request]" in report
    assert "retry\\path" in report
    assert "Levels: CRITICAL=1, ERROR=1, WARNING=1, INFO=1, DEBUG=0" in report
    print("REPRO_OK")


if __name__ == "__main__":
    main()
PY
chmod +x /app/repro_case.py
