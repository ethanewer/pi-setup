#!/usr/bin/env python3
import argparse
import json
import re
import sys
from datetime import datetime
from typing import Iterable

LEVELS = ("CRITICAL", "ERROR", "WARNING", "INFO", "DEBUG")
_REQUIRED = {"id", "timestamp", "level", "component", "message"}
_ALLOWED = _REQUIRED | {"tags"}
_TIMESTAMP = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")


def _has_control(value):
    return any(ord(c) <= 0x1F or 0x7F <= ord(c) <= 0x9F for c in value)


def _fail(position, reason):
    return ValueError(f"line {position}: {reason}")


def _reject_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON field")
        result[key] = value
    return result


def _parse_lines(lines):
    records = []
    seen_ids = set()
    for position, raw in enumerate(lines, 1):
        line = raw[:-1] if raw.endswith("\n") else raw
        if line.endswith("\r"):
            line = line[:-1]
        if line == "":
            raise _fail(position, "blank line")
        try:
            value = json.loads(line, object_pairs_hook=_reject_duplicate_keys)
        except (json.JSONDecodeError, TypeError, ValueError) as exc:
            raise _fail(position, "malformed JSON") from exc
        if not isinstance(value, dict):
            raise _fail(position, "record must be an object")
        if set(value) not in (_REQUIRED, _ALLOWED):
            raise _fail(position, "wrong fields")
        for field in _REQUIRED:
            if not isinstance(value[field], str):
                raise _fail(position, f"{field} must be a string")
            if value[field] == "":
                raise _fail(position, f"{field} must not be empty")
            if _has_control(value[field]):
                raise _fail(position, f"{field} contains a control character")
        if value["id"] in seen_ids:
            raise _fail(position, "duplicate id")
        seen_ids.add(value["id"])
        if value["level"] not in LEVELS:
            raise _fail(position, "unsupported level")
        timestamp = value["timestamp"]
        if not _TIMESTAMP.fullmatch(timestamp):
            raise _fail(position, "invalid timestamp")
        try:
            datetime.strptime(timestamp, "%Y-%m-%dT%H:%M:%SZ")
        except ValueError as exc:
            raise _fail(position, "invalid timestamp") from exc
        if "tags" in value:
            tags = value["tags"]
            if not isinstance(tags, list) or not tags:
                raise _fail(position, "tags must be a non-empty list")
            for tag in tags:
                if not isinstance(tag, str) or not tag:
                    raise _fail(position, "tags must contain non-empty strings")
                if _has_control(tag):
                    raise _fail(position, "tags contain a control character")
        records.append({"record": value, "position": position - 1})
    return records


def build_report(lines: Iterable[str]) -> str:
    records = _parse_lines(lines)
    counts = {level: 0 for level in LEVELS}
    ordered_events = sorted(records, key=lambda e: (e["record"]["timestamp"], e["position"]))
    component_counts = {}
    component_first = {}
    for event_position, entry in enumerate(ordered_events):
        record = entry["record"]
        counts[record["level"]] += 1
        component = record["component"]
        component_counts[component] = component_counts.get(component, 0) + 1
        component_first.setdefault(component, event_position)
    ordered_components = sorted(component_counts, key=lambda n: (-component_counts[n], component_first[n], n))
    component_text = ", ".join(f"{n}={component_counts[n]}" for n in ordered_components) if ordered_components else "none=0"
    output = [
        "Log triage report",
        f"Records: {len(records)}",
        "Levels: " + ", ".join(f"{level}={counts[level]}" for level in LEVELS),
        f"Components: {component_text}",
        "Events:",
    ]
    output.extend(
        f"[{e['record']['timestamp']}] {e['record']['level']} {e['record']['component']}: {e['record']['message']}"
        for e in ordered_events
    )
    return "\n".join(output) + "\n"


def _main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)
    try:
        with open(args.input, "r", encoding="utf-8", newline="") as source:
            contents = source.read()
        report = build_report(contents.splitlines()) if contents else build_report([])
        with open(args.output, "w", encoding="utf-8", newline="") as destination:
            destination.write(report)
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"triage: {exc}", file=sys.stderr)
        return 1
    return 0

if __name__ == "__main__":
    raise SystemExit(_main())
