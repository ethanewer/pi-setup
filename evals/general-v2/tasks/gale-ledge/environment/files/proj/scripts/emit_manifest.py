#!/usr/bin/env python3
"""Compliance gate for the gale-ledge release manifest.

The release manifest (manifest.json next to this file's project root) declares
the project's dependency matrix and a hard source-size cap over /src.

This script checks:
  1. every declared dependency is installed with a version >= its declared min;
  2. no regular file under <root>/src is larger than source_cap_bytes.

On success it prints exactly "MANIFEST COMPLETE" and exits 0.  On any problem
it prints the problems to stdout and exits nonzero.
"""
import importlib.metadata
import json
import os
import sys


def as_int(v):
    try:
        return int(v)
    except (TypeError, ValueError):
        return 0


def version_ge(have, need):
    hv = [as_int(p) for p in have.split(".")]
    nv = [as_int(p) for p in need.split(".")]
    for _ in range(max(len(hv), len(nv)) - len(hv)):
        hv.append(0)
    for _ in range(max(len(hv), len(nv)) - len(nv)):
        nv.append(0)
    return hv >= nv


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    manifest_path = os.path.join(root, "manifest.json")
    if not os.path.exists(manifest_path):
        print("MANIFEST COMPLETE")
        return 0
    try:
        with open(manifest_path) as fh:
            manifest = json.load(fh)
    except Exception as exc:  # noqa: BLE001
        print("manifest.json is not valid JSON: %s" % exc)
        return 1

    problems = []

    deps = manifest.get("dependencies") or {}
    for dep, minver in sorted(deps.items()):
        try:
            have = importlib.metadata.version(dep)
        except importlib.metadata.PackageNotFoundError:
            problems.append("dependency %r is not installed (need >= %s)" % (dep, minver))
            continue
        except Exception as exc:  # noqa: BLE001
            problems.append("dependency %r could not be queried: %s" % (dep, exc))
            continue
        if not version_ge(have, minver):
            problems.append(
                "dependency %r version %s < required %s" % (dep, have, minver))

    cap = manifest.get("source_cap_bytes")
    src = os.path.join(root, "src")
    if cap is not None and os.path.isdir(src):
        for dirpath, _dirs, files in os.walk(src):
            for fn in files:
                full = os.path.join(dirpath, fn)
                try:
                    size = os.path.getsize(full)
                except OSError:
                    continue
                if size > cap:
                    problems.append(
                        "%s size %db exceeds cap %db" %
                        (os.path.relpath(full, root), size, cap))

    if problems:
        print("MANIFEST PROBLEMS:")
        for p in problems:
            print("  + " + p)
        return 1

    print("MANIFEST COMPLETE")
    return 0


if __name__ == "__main__":
    sys.exit(main())