#!/usr/bin/env bash
# quartz-orchid oracle: produces every deliverable with real work.
set -euo pipefail

# ---- /app/mkarchive.sh -----------------------------------------------------
cat > /app/mkarchive.sh <<'SH'
#!/usr/bin/env bash
# Reproducible GNU tar: symlinks kept as links, GNU long-name format for long/
# deep names, every member mtime == BUILD_EPOCH (else fallback 1630454400),
# members sorted by name, owner/group normalized to 0.
set -euo pipefail

SRC_DIR="${1:-/app/src}"
OUT_TAR="${2:-/app/reproduce.tar}"

EPOCH="${BUILD_EPOCH:-1630454400}"
case "$EPOCH" in
  (*[!0-9]*|'') echo "mkarchive: invalid BUILD_EPOCH: '$EPOCH' (must be integer seconds)" >&2; exit 2;;
esac

mkdir -p "$(dirname "$OUT_TAR")"

cd "$SRC_DIR"
# %P = member path relative to the search root (no leading "./"), null too.
find . -mindepth 1 \( -type f -o -type l \) -printf '%P\0' \
  | tar --null --files-from=- \
        --format=gnu \
        --sort=name \
        --owner=0 --group=0 --numeric-owner \
        --mode=0644 \
        --mtime="@$EPOCH" \
        -cf "$OUT_TAR"
SH
chmod +x /app/mkarchive.sh

# Build the visible reproducible archive with the fallback epoch (no env set).
env -u BUILD_EPOCH /app/mkarchive.sh          # -> /app/reproduce.tar

# ---- /app/split.py ----------------------------------------------------------
cat > /app/split.py <<'PY'
#!/usr/bin/env python3
"""Split an oversized record into capsized, reassembleable chunks."""
import json
import math
import os
import sys


def err(msg):
    print(msg, file=sys.stderr)


def out_split(inp, cap_s, outdir):
    if inp is None or not os.path.exists(inp):
        err(f"split: no such file: {inp}")
        return 2
    if os.path.isdir(inp):
        err(f"split: not a regular file: {inp}")
        return 2
    try:
        cap = int(cap_s)
    except (TypeError, ValueError):
        err(f"split: invalid CAP: {cap_s!r} (expected a positive integer)")
        return 1
    if cap < 1:
        err(f"split: CAP must be a positive integer, got {cap}")
        return 1
    with open(inp, "rb") as fh:
        data = fh.read()
    os.makedirs(outdir, exist_ok=True)
    size = len(data)
    k = (size + cap - 1) // cap if size else 0
    for i in range(k):
        with open(os.path.join(outdir, f"chunk_{i:06d}"), "wb") as fh:
            fh.write(data[i * cap:(i + 1) * cap])
    manifest = {
        "input": os.path.basename(inp),
        "size": size,
        "cap": cap,
        "chunks": k,
        "pad": 6,
    }
    with open(os.path.join(outdir, "manifest.json"), "w") as fh:
        json.dump(manifest, fh)
    return 0


def out_join(outdir, output):
    manifest_path = os.path.join(outdir, "manifest.json")
    if not os.path.exists(manifest_path):
        err(f"split: join: no manifest in {outdir}")
        return 3
    with open(manifest_path) as fh:
        m = json.load(fh)
    size = int(m["size"])
    k = int(m["chunks"])
    pad = int(m.get("pad", 6))
    pieces = []
    for i in range(k):
        p = os.path.join(outdir, f"chunk_{i:0{pad}d}")
        if not os.path.exists(p):
            err(f"split: join: missing chunk {p}")
            return 3
        with open(p, "rb") as fh:
            pieces.append(fh.read())
    out = b"".join(pieces)[:size]
    with open(output, "wb") as fh:
        fh.write(out)
    return 0


def main(argv):
    if len(argv) >= 2 and argv[1] == "split":
        if len(argv) < 5:
            err("usage: split.py split INPUT CAP OUT_DIR")
            return 1
        return out_split(argv[2], argv[3], argv[4])
    if len(argv) >= 2 and argv[1] == "join":
        if len(argv) < 4:
            err("usage: split.py join OUT_DIR OUTPUT")
            return 1
        return out_join(argv[2], argv[3])
    err("usage: split.py split INPUT CAP OUT_DIR | split.py join OUT_DIR OUTPUT")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY
chmod +x /app/split.py

# ---- /app/extract.txt -------------------------------------------------------
# Extract payload_secret.txt from the encrypted 7z with the recovered password.
PW="$(cat /app/credentials/key.txt)"
7z x -bd -y -p"$PW" -so /app/vault.7z payload_secret.txt > /app/extract.txt

# ---- /app/digester.py --------------------------------------------------------
cat > /app/digester.py <<'PY'
#!/usr/bin/env python3
"""PBKDF2-HMAC-SHA256 digest of every regular file in a tree."""
import hashlib
import os
import sys

SALT = "ff4c8e17b3013d38f6a9c71b0d21e44a"
ITER = 100000


def main(argv):
    treedir = argv[1] if len(argv) > 1 else "/app/tree"
    output = argv[2] if len(argv) > 2 else None
    lines = []
    for root, _, files in os.walk(treedir):
        for name in sorted(files):
            p = os.path.join(root, name)
            if not os.path.isfile(p):
                continue
            with open(p, "rb") as fh:
                data = fh.read()
            dk = hashlib.pbkdf2_hmac(
                "sha256", data, bytes.fromhex(SALT), ITER, dklen=32
            )
            rel = os.path.relpath(p, treedir).replace(os.sep, "/")
            lines.append(f"{rel}\t{dk.hex()}")
    lines.sort()
    text = "\n".join(lines) + ("\n" if lines else "")
    if output:
        with open(output, "w") as fh:
            fh.write(text)
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main(sys.argv)
PY
chmod +x /app/digester.py

# Regenerate the visible digests over /app/tree.
python3 /app/digester.py /app/tree /app/digests.txt

echo "solve done"
ls -l /app/reproduce.tar /app/extract.txt /app/digests.txt /app/split.py /app/mkarchive.sh /app/digester.py