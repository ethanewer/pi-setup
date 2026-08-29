#!/usr/bin/env python3
"""kayak-qd -- molecular catalog loader/filter.

Reads a molecule catalog JSON file (a JSON array of molecule dicts, each with at
least a ``name`` field) at a *runtime* path and returns the entries whose name
matches, case-insensitively, any name in a supplied name list.  Matching is done
on the trimmed (surrounding whitespace removed) name; a molecule whose entry has
no usable ``name`` value is skipped.  The result preserves catalog order and is
truncated to an optional result limit.

Also exposes a small CLI so the module can be run as:
    python3 load_catalog.py --catalog CATALOG.json --names NAMES.txt \\
        [--limit N] [--out OUT.json]
"""
from __future__ import annotations

import argparse
import json
import sys
from typing import List, Optional, Sequence


def filter_catalog(
    catalog_path: str,
    names: Sequence[str],
    limit: Optional[int] = 1000,
) -> List[dict]:
    """Return catalog entries whose trimmed name matches any of `names`
    case-insensitively, in catalog order, truncated to `limit`.

    Re-reads the JSON file from disk on every call (no caching).
    """
    with open(catalog_path, "r", encoding="utf-8") as fh:
        catalog = json.load(fh)

    wanted = {str(n).strip().lower() for n in names if str(n).strip()}

    result: List[dict] = []
    for entry in catalog:
        raw = entry.get("name") if isinstance(entry, dict) else None
        if isinstance(raw, str) and raw.strip() and raw.strip().lower() in wanted:
            result.append(entry)
            if limit is not None and len(result) >= limit:
                break
    return result


def _wanted_from_file(names_path: Optional[str]) -> List[str]:
    if not names_path:
        return []
    with open(names_path, "r", encoding="utf-8") as fh:
        return [ln for ln in fh.read().splitlines()]


def main(argv: Optional[Sequence[str]] = None) -> int:
    ap = argparse.ArgumentParser(description="Filter a molecular catalog JSON.")
    ap.add_argument("--catalog", required=False, help="path to catalog JSON array")
    ap.add_argument("--names", required=False, help="file with one name per line")
    ap.add_argument("--limit", type=int, default=1000,
                    help="max matches to return (default 1000; use 0 for unlimited)")
    ap.add_argument("--out", required=True, help="output JSON array path")
    args = ap.parse_args(argv)

    if not args.catalog:
        print("error: --catalog is required", file=sys.stderr)
        return 2

    names = _wanted_from_file(args.names)
    limit = None if args.limit <= 0 else args.limit
    try:
        filtered = filter_catalog(args.catalog, names, limit)
    except Exception as exc:  # malformed catalog / IO errors
        print("error: %s" % exc, file=sys.stderr)
        return 1

    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(filtered, fh, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())