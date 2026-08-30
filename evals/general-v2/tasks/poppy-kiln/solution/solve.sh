#!/bin/bash
# Oracle for poppy-kiln: author the skeleton-restorer program, then RUN it on
# the visible catalog to produce /app/skeleton. Never reads /tests.
set -eu

SOLVER="/app/skeleton.py"

# ---- 1. Write the deliverable program (this IS the work).
cat > "$SOLVER" <<'PY'
import os
import re
import sys

ENTRY_RE = re.compile(r"^([0-9a-f]{64})  (.+)$")


def parse_catalog(path):
    """Return the list of file paths, or raise ValueError with a reason."""
    files = []
    with open(path, "r", encoding="utf-8") as fh:
        for lineno, raw in enumerate(fh, 1):
            line = raw.rstrip("\n").rstrip("\r")
            if not line.strip():
                continue
            if line.lstrip().startswith("#"):
                continue
            m = ENTRY_RE.match(line)
            if not m:
                raise ValueError("line %d: malformed entry" % lineno)
            rel = m.group(2)
            if rel.startswith("/"):
                raise ValueError("line %d: absolute path %r" % (lineno, rel))
            parts = rel.split("/")
            if any(part == ".." for part in parts):
                raise ValueError("line %d: '..' component in %r" % (lineno, rel))
            if rel in files:
                continue
            # file/directory conflict against previously accepted entries
            for earlier in files:
                if rel.startswith(earlier + "/"):
                    raise ValueError(
                        "line %d: %r conflicts with file entry %r"
                        % (lineno, rel, earlier)
                    )
            files.append(rel)
    # conflict where a later entry is a parent directory of an earlier file
    for i, a in enumerate(files):
        for j, b in enumerate(files):
            if i != j and b.startswith(a + "/"):
                raise ValueError("file/directory conflict: %r vs %r" % (a, b))
    return files


def main():
    if len(sys.argv) != 3:
        print("usage: python3 skeleton.py <catalog> <outdir>", file=sys.stderr)
        return 2
    catalog, outdir = sys.argv[1], sys.argv[2]
    try:
        files = parse_catalog(catalog)
    except (OSError, ValueError) as exc:
        print("skeleton: refusing to build: %s" % exc, file=sys.stderr)
        return 1
    os.makedirs(outdir, exist_ok=True)
    for rel in files:
        dest = os.path.join(outdir, *rel.split("/"))
        parent = os.path.dirname(dest)
        if parent:
            os.makedirs(parent, exist_ok=True)
        with open(dest, "wb"):
            pass  # create/truncate to exactly zero bytes
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY

chmod +x "$SOLVER"

# 2. Produce the visible artifact.
python3 "$SOLVER" /app/catalog.txt /app/skeleton

echo "solve.sh done -> $SOLVER and /app/skeleton"
ls -lR /app/skeleton | head -40
