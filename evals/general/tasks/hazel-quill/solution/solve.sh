#!/bin/bash
# Oracle for hazel-quill: author the unquarantine program, then RUN it on the
# visible quarantine directory. Never reads /tests.
set -eu

SOLVER="/app/unquarantine.py"

# ---- 1. Write the deliverable program (this IS the work).
cat > "$SOLVER" <<'PY'
import base64
import os
import shutil
import sys


def decode_name(segment):
    """Return the original filename for a .qtn segment, or None if invalid."""
    if not segment:
        return None
    try:
        raw = base64.b64decode(segment, validate=True)
    except Exception:
        return None
    if not raw:
        return None
    try:
        name = raw.decode("utf-8")
    except UnicodeDecodeError:
        return None
    if not name or "/" in name or "\x00" in name or name in (".", ".."):
        return None
    return name


def main():
    if len(sys.argv) != 3:
        print("usage: python3 unquarantine.py <input_dir> <output_dir>",
              file=sys.stderr)
        return 2
    input_dir, output_dir = sys.argv[1], sys.argv[2]
    if not os.path.isdir(input_dir):
        print("unquarantine: input dir not found: %s" % input_dir,
              file=sys.stderr)
        return 2

    restored_dir = os.path.join(output_dir, "restored")
    os.makedirs(restored_dir, exist_ok=True)

    recovered = {}
    for entry in sorted(os.listdir(input_dir)):
        full = os.path.join(input_dir, entry)
        if not entry.endswith(".qtn"):
            continue
        if not os.path.isfile(full) or os.path.islink(full):
            continue
        segment = entry[:-len(".qtn")]
        name = decode_name(segment)
        if name is None:
            continue
        shutil.copyfile(full, os.path.join(restored_dir, name))
        recovered[name] = entry  # later processed files win on collision

    with open(os.path.join(output_dir, "recovered.txt"), "w",
              encoding="utf-8") as fh:
        for name in sorted(recovered):
            fh.write(name + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY

chmod +x "$SOLVER"

# 2. Produce the visible artifacts from the shipped quarantine.
python3 "$SOLVER" /app/quarantine /app

echo "solve.sh done -> $SOLVER /app/recovered.txt /app/restored"
cat /app/recovered.txt
