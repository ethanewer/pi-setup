#!/usr/bin/env bash
# umber-mantle oracle.
#
# Writes the reusable solver /app/build.sh, then runs it against /app to produce
# the three deliverable artifacts. Never reads /tests.
set -euo pipefail

cat > /app/build.sh <<'EOF'
#!/usr/bin/env bash
# Reusable solver for the umber-mantle task.
#
#   build.sh [BASE_DIR]        (BASE_DIR defaults to /app)
#
# From an input tree rooted at $BASE (with data/, place/, payloads/ subdirs)
# produces, inside $BASE:
#   $BASE/out.tar.gz   gzipped tar of data/ keeping the leading `data/` component,
#                      excluding caches, vendored deps, build objects, version
#                      metadata and restricted-permission files
#   $BASE/decoded.raw  the uncompressed printer-file fixture from place/
#   $BASE/out.bin      the binary reassembled from the hexdump streamed out of
#                      map.hex inside payloads/archive.tar.gz (archive NOT
#                      expanded; payloads/raw.log must stay untouched)
#
# The script is deliberately generic (drives a python core) so test.sh can
# re-run it against hidden input trees in fresh working directories.
set -euo pipefail
BASE="${1:-/app}"
exec python3 - "$BASE" <<'PY'
import os, re, sys, glob, tarfile

base = sys.argv[1]

# ---------------------------------------------------------------- 1 out.tar.gz
data = os.path.join(base, "data")
BANNED_DIRS = ("__pycache__", "third_party", "local")

def excluded(rel: str) -> bool:
    parts = rel.split("/")
    if any(p in BANNED_DIRS for p in parts):
        return True
    if parts[-1] == "version.manifest":
        return True
    if parts[-1].endswith((".o", ".pyc")):
        return True
    # restricted-permission files: world has no read bit -> excluded
    st = os.stat(os.path.join(data, rel))
    if not (st.st_mode & 0o004):
        return True
    return False

if os.path.isdir(data):
    with tarfile.open(os.path.join(base, "out.tar.gz"), "w:gz",
                      format=tarfile.GNU_FORMAT) as tar:
        for root, dirs, files in os.walk(data):
            dirs[:] = [d for d in dirs if d not in BANNED_DIRS]
            rel_root = os.path.relpath(root, data)
            for f in files:
                rel = f if rel_root == "." else os.path.join(rel_root, f)
                if excluded(rel):
                    continue
                tar.add(os.path.join(root, f), arcname="data/" + rel)

# -------------------------------------------------------------- 2 decoded.raw
printers = sorted(glob.glob(os.path.join(base, "place", "*.printer")))
if len(printers) != 1:
    raise SystemExit("expected exactly one printer fixture under place/")
raw = open(printers[0], "rb").read()
decoded = __import__("gzip").decompress(raw) if raw[:2] == b"\x1f\x8b" else raw
with open(os.path.join(base, "decoded.raw"), "wb") as f:
    f.write(decoded)

# ---------------------------------------------------------------- 3 out.bin
# Stream ONLY the map.hex member out of the archive (never expand the whole
# archive), then reassemble the hexdump back into the binary artifact.
arch = os.path.join(base, "payloads", "archive.tar.gz")
HEX = re.compile(r"^[0-9a-fA-F]{2}$")
hexbytes = bytearray()
with tarfile.open(arch, "r:gz") as tf:
    body = tf.extractfile("map.hex").read().decode()
    for line in body.splitlines():
        for tok in line.split():
            if HEX.match(tok):
                hexbytes.extend(bytes.fromhex(tok))
with open(os.path.join(base, "out.bin"), "wb") as f:
    f.write(bytes(hexbytes))

print("build.sh: %s done" % base)
PY
EOF
chmod +x /app/build.sh

# Materialize the deliverables for the shipped input tree.
bash /app/build.sh /app

echo "solve.sh complete"
ls -l /app/out.tar.gz /app/decoded.raw /app/out.bin /app/build.sh