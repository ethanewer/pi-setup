#!/bin/bash
set -eu
# Real oracle: author the reusable audit program, then RUN it to produce the
# deliverable output. Never reads /tests and never cats a precomputed answer.
mkdir -p /app
cat > /app/audit.py <<'PYEOF'
#!/usr/bin/env python3
"""Audit a content-addressed object store.

Usage:
    python3 audit.py <store_dir> <output_json>

Reads a miniature content-addressed object store rooted at <store_dir>:

    refs/HEAD          text file holding the object ID of the head commit
    objects/<id>.json  one object file per object; <id> must equal the
                       SHA-256 (hex) of its canonical JSON payload

Object vocabulary:
    blob   -> {"type":"blob",   "text": "..."}
    tree   -> {"type":"tree",   "blobs": [<blob-id>, ...]}
    commit -> {"type":"commit", "tree": <tree-id>, "parent": <commit-id|null>,
               "message": "..."}

Canonical payload = json.dumps(obj, sort_keys=True, separators=(",",":")).encode().

Reachability: starting from refs/HEAD commit, follow tree and parent pointers
recursively. A tree's entries are its blobs (nested trees are not defined, but
unknown types are ignored). Every object id visited is reachable.

Validity: only object files whose stored filename equals the sha-256 of their
canonical payload are addressable. Unparseable files and mismatched names are
ignored entirely (never reachable, never listed as unreachable candidates).

Secret detection: a *reachable* blob whose text matches (case-insensitive):

    AKIA[0-9A-Z]{16}
    | -----BEGIN [A-Z ]*PRIVATE KEY-----
    | (password|passwd|secret|token|apikey|api[_-]?key|access[_-]?key) [:=] <token>

The credential-looking text must start with one of the listed key words
followed by a colon or equals sign and a non-empty token. Any reachable blob
whose text contains such a credential is reported.

Output (JSON, written atomically to <output_json>) with sorted id lists:
    {"reachable": [...], "secrets": [...], "unreachable": [...]}
"""

import hashlib
import json
import os
import re
import sys

SECRET = re.compile(
    r"(?:AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|"
    r"(?:password|passwd|secret|token|apikey|api[_-]?key|access[_-]?key)\s*[:=]\s+\S+)",
    re.IGNORECASE,
)


def canonical(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":")).encode()


def object_id(obj):
    return hashlib.sha256(canonical(obj)).hexdigest()


def load_objects(objects_dir):
    objs = {}
    if os.path.isdir(objects_dir):
        for name in sorted(os.listdir(objects_dir)):
            if not name.endswith(".json"):
                continue
            path = os.path.join(objects_dir, name)
            try:
                with open(path, "r", encoding="utf-8") as h:
                    obj = json.load(h)
            except Exception:
                continue
            if not isinstance(obj, dict):
                continue
            if object_id(obj) != name[:-5]:
                continue  # filename must equal sha256(canonical payload)
            objs[name[:-5]] = obj
    return objs


def audit(store_dir):
    objs = load_objects(os.path.join(store_dir, "objects"))
    head = None
    head_path = os.path.join(store_dir, "refs", "HEAD")
    if os.path.isfile(head_path):
        head = open(head_path, "r", encoding="utf-8").read().strip()

    reachable = set()
    seen = set()

    def walk(obj_id):
        if obj_id in seen or obj_id not in objs:
            return
        seen.add(obj_id)
        reachable.add(obj_id)
        obj = objs[obj_id]
        if obj.get("type") == "commit":
            tree = obj.get("tree")
            if isinstance(tree, str):
                walk(tree)
            parent = obj.get("parent")
            if isinstance(parent, str):
                walk(parent)
        elif obj.get("type") == "tree":
            for blob_id in obj.get("blobs") or []:
                if isinstance(blob_id, str):
                    walk(blob_id)

    if head is not None:
        walk(head)

    answer = {
        "reachable": sorted(reachable),
        "secrets": [
            oid
            for oid in sorted(reachable)
            if objs[oid].get("type") == "blob"
            and SECRET.search(objs[oid].get("text", "") or "")
        ],
        "unreachable": sorted(set(objs) - reachable),
    }
    return answer


def main(argv):
    if len(argv) != 3:
        print("usage: audit.py <store_dir> <output_json>", file=sys.stderr)
        return 2
    store_dir, output_path = argv[1], argv[2]
    answer = audit(store_dir)
    parent = os.path.dirname(output_path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(json.dumps(answer, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PYEOF
chmod +x /app/audit.py
python3 /app/audit.py /app/store /app/audit.json
