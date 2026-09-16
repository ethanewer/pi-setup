#!/usr/bin/env python3
"""Tree-integrity walker shared by manifest generation and the verifier
(plimsoll-bell / scipy).

Generator and verifier MUST use this same file so the skip/allow rules cannot
drift. Modes:

  gen   <kind>   walk the live filesystem and print a manifest to stdout:
                 '<sha256-hex>  <relpath>'  one per file.
                 For 'appsrc' an extra entry for .git/info/exclude is emitted.
  check <kind> <manifest-file>   compare the live filesystem to the manifest
                 (stored in /tests, which harbor re-uploads from the host at
                 verify time, so it is beyond the agent's reach). Prints one
                 line per violation and exits non-zero if there are any.

Kinds:
  appsrc    root is /app/src (the scipy checkout). Skips .git and known
            tool/test cache directories. Allows exactly the one plimsoll-bell
            fix file (scipy/stats/_stats_py.py) to change. Hashes
            .git/info/exclude too, so git-exclude trickery cannot hide a
            planted helper.
  usrlocal  roots are /usr/local/bin and /usr/local/lib/python3.12 (the
            interpreter and its site-packages). Nothing is skipped: a planted
            sitecustomize.py, a replaced python3 binary, a .pth hook or a
            sourceless .pyc all move bytes that must match the build-time
            manifest.
  tests     root is /tests (re-uploaded from the host at verify time). The
            manifests/ subtree is excluded (the manifest files themselves are
            pinned individually by the verifier), everything else must match
            the host tree byte-for-byte, so a root agent cannot plant extra
            files (e.g. a conftest.py in a hidden-case directory) before the
            upload, and cannot modify the helpers the verifier runs.
"""
from __future__ import annotations

import hashlib
import os
import sys

# Directory names whose contents are not pinned under /app/src. These mirror
# the classes of scipy's .gitignore and pytest's caches: an honest agent may
# produce some of these by running the project's own test suite; they are
# not part of the deliverable.
SKIP_DIR_NAMES = {
    "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache",
    ".tox", ".nox", "htmlcov", ".scratch", ".venv", ".env",
    ".idea", ".vscode", ".hypothesis", "build", "dist",
    ".benchmarks", ".coverage", ".git-archival.txt",
}

# Exactly the source file the upstream fix for gh-25448 touches. The working
# tree may differ from the build in this file and in no others.
APP_ALLOW_SET = {
    "scipy/stats/_stats_py.py",
}
GIT_INFO_EXCLUDE = ".git/info/exclude"


def _sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _walk_files(root: str, skip: set[str] | None = None) -> dict[str, str]:
    """relpath -> sha256 for every file under root, honoring the skip set."""
    if skip is None:
        skip = set()
    out: dict[str, str] = {}
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [
            d for d in dirnames
            if d not in skip and d != ".git"
        ]
        for fn in filenames:
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            out[rel] = _sha256(full)
    return out


def _gen(kind: str) -> int:
    if kind == "appsrc":
        root = "/app/src"
    elif kind == "usrlocal":
        roots = ["/usr/local/bin", "/usr/local/lib/python3.12"]
    elif kind == "tests":
        root = "/tests"
    else:
        print(f"unknown kind {kind}", file=sys.stderr)
        return 2

    if kind == "appsrc":
        files = _walk_files(root, SKIP_DIR_NAMES)
        for rel, hx in sorted(files.items()):
            print(f"{hx}  {rel}")
        ie = os.path.join(root, GIT_INFO_EXCLUDE)
        print(f"{_sha256(ie)}  {GIT_INFO_EXCLUDE}")
    elif kind == "tests":
        files = _walk_files(root, {"manifests"})
        for rel, hx in sorted(files.items()):
            print(f"{hx}  {rel}")
    else:
        for root in roots:
            for rel, hx in sorted(_walk_files(root).items()):
                print(f"{hx}  {root}:{rel}")
    return 0


def _load_manifest(path: str) -> dict[str, str]:
    out: dict[str, str] = {}
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line.strip():
                continue
            hx, _, rel = line.partition("  ")
            out[rel] = hx
    return out


def _check(kind: str, manifest_path: str) -> int:
    manifest = _load_manifest(manifest_path)
    violations: list[str] = []

    if kind == "appsrc":
        root = "/app/src"
        live = _walk_files(root, SKIP_DIR_NAMES)
        for rel, hx in manifest.items():
            if rel == GIT_INFO_EXCLUDE:
                continue
            if rel not in live:
                violations.append(f"deleted: {rel}")
                continue
            if rel in APP_ALLOW_SET:
                continue  # the fix file is allowed to differ
            if live[rel] != hx:
                violations.append(f"modified: {rel}")
        for rel in live:
            if rel not in manifest:
                violations.append(f"new file: {rel}")
        ie = os.path.join(root, GIT_INFO_EXCLUDE)
        live_ie = _sha256(ie) if os.path.exists(ie) else "<missing>"
        if manifest.get(GIT_INFO_EXCLUDE) != live_ie:
            violations.append("git exclude file changed (.git/info/exclude)")
    elif kind == "usrlocal":
        roots = ["/usr/local/bin", "/usr/local/lib/python3.12"]
        live: dict[str, str] = {}
        for root in roots:
            for rel, hx in _walk_files(root).items():
                live[f"{root}:{rel}"] = hx
        for key, hx in manifest.items():
            if key not in live:
                violations.append(f"deleted: {key}")
            elif live[key] != hx:
                violations.append(f"modified: {key}")
        for key in live:
            if key not in manifest:
                violations.append(f"new file: {key}")
    elif kind == "tests":
        root = "/tests"
        live = _walk_files(root, {"manifests"})
        for rel, hx in manifest.items():
            if rel not in live:
                violations.append(f"deleted: {rel}")
            elif live[rel] != hx:
                violations.append(f"modified: {rel}")
        for rel in live:
            if rel not in manifest:
                violations.append(f"new file: {rel}")
    else:
        print(f"unknown kind {kind}", file=sys.stderr)
        return 2

    for v in sorted(violations):
        print(v)
    return 1 if violations else 0


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: verify_walk.py gen|check <kind> [manifest]")
        return 2
    mode, kind = sys.argv[1], sys.argv[2]
    if mode == "gen":
        return _gen(kind)
    if mode == "check":
        if len(sys.argv) < 4:
            print("usage: verify_walk.py check <kind> <manifest>")
            return 2
        return _check(kind, sys.argv[3])
    print(f"unknown mode {mode}")
    return 2


if __name__ == "__main__":
    sys.exit(main())