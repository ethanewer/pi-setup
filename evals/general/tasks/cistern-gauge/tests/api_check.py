#!/usr/bin/env python3
"""Public API surface check for the cistern-gauge reactor.

Compares the javap(-public -s) surface of the freshly built classes under
<repo-root>/*/target/classes with the pristine baseline recorded in
api-baseline.json. Only DELETIONS fail: an implementation may add public
members, but may not remove a baseline class or member.

Usage:
    python3 api_check.py <repo-root> <baseline.json>   # check (exit 0/1)
    python3 api_check.py --emit <repo-root> <out.json> # record baseline
"""

import json
import subprocess
import sys
from pathlib import Path


def class_files(classes_dir):
    """Map fully-qualified class name -> class file (inner classes skipped)."""
    found = {}
    root = Path(classes_dir)
    if not root.is_dir():
        return found
    for path in root.rglob("*.class"):
        if "$" in path.name:  # inner / synthetic / lambda classes
            continue
        rel = path.relative_to(root)
        fqcn = ".".join(rel.with_suffix("").parts)
        found[fqcn] = path
    return found


def javap_members(classes_dir, fqcn):
    """Public member descriptors of one class, or None if javap fails."""
    result = subprocess.run(
        ["javap", "-public", "-s", "-classpath", str(classes_dir), fqcn],
        capture_output=True, text=True)
    if result.returncode != 0:
        return None
    members = []
    for raw in result.stdout.splitlines():
        line = raw.strip()
        if line.endswith(";"):
            members.append(line)
        elif "class" in line and "{" in line and not line.startswith("public class"):
            # nested public class declarations (e.g. records, enums)
            members.append(line.rstrip("{" ).strip())
    return members


def surface(repo_root):
    """{ fqcn: sorted member descriptors } across every cistern-* module."""
    surface = {}
    for module in sorted(repo_root.glob("cistern-*")):
        classes_dir = module / "target" / "classes"
        if not classes_dir.is_dir():
            continue
        for fqcn in class_files(classes_dir):
            members = javap_members(classes_dir, fqcn)
            if members is not None:
                surface[fqcn] = sorted(set(members))
    return surface


def main():
    args = sys.argv[1:]
    if not args:
        print("usage: api_check.py [--emit] <repo-root> <json-path>", file=sys.stderr)
        return 2
    if args[0] == "--emit":
        repo_root, out = Path(args[1]), Path(args[2])
        recorded = surface(repo_root)
        out.write_text(json.dumps(recorded, indent=1, sort_keys=True) + "\n")
        print("baseline emitted: %d classes" % len(recorded))
        return 0
    repo_root, baseline_path = Path(args[0]), Path(args[1])
    baseline = json.loads(baseline_path.read_text())
    current = surface(repo_root)
    problems = []
    for fqcn in sorted(baseline):
        if fqcn not in current:
            problems.append("CLASS DELETED: " + fqcn)
            continue
        for member in baseline[fqcn]:
            if member not in current[fqcn]:
                problems.append("MEMBER DELETED in " + fqcn + ": " + member)
    if problems:
        print("PUBLIC API DELETIONS DETECTED:")
        for problem in problems:
            print("  - " + problem)
        return 1
    print("api surface intact (%d baseline classes checked)" % len(baseline))
    return 0


if __name__ == "__main__":
    sys.exit(main())