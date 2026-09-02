#!/usr/bin/env bash
# Oracle for silt-barrow.
# Writes the reusable member-streaming script /app/extract.sh, then runs it on
# the visible bundle to produce /app/out/crash.mkd. Never reads /tests.
set -eu

cat > /app/extract.sh <<'EOF'
#!/usr/bin/env bash
# silt-barrow member streamer.
#
#   extract.sh [BASE]      (BASE defaults to /app)
#
# Streams ONLY the crash.mkd member out of $BASE/bundle/incident.tar.gz and
# writes its exact bytes to $BASE/out/crash.mkd. No other member is ever
# materialized (the archive carries sensitive hostkeys.pem and a recorder.log
# member that would clobber the live log), and the archive and the live log
# are left byte-identical.
set -euo pipefail
BASE="${1:-/app}"
exec python3 - "$BASE" <<'PY'
import os
import sys
import tarfile

base = sys.argv[1]
arch = os.path.join(base, "bundle", "incident.tar.gz")
out_dir = os.path.join(base, "out")
os.makedirs(out_dir, exist_ok=True)

with tarfile.open(arch, "r:gz") as tf:
    names = tf.getnames()
    if names.count("crash.mkd") != 1:
        raise SystemExit("expected exactly one crash.mkd member, found %d" % names.count("crash.mkd"))
    src = tf.extractfile("crash.mkd")
    if src is None:
        raise SystemExit("crash.mkd is not a regular file")
    data = src.read()          # stream the single wanted member; nothing else

with open(os.path.join(out_dir, "crash.mkd"), "wb") as fh:
    fh.write(data)
print("wrote %s (%d bytes)" % (os.path.join(out_dir, "crash.mkd"), len(data)))
PY
EOF
chmod +x /app/extract.sh

# Materialize the visible deliverable.
bash /app/extract.sh /app

echo "silt-barrow oracle OK"
ls -l /app/extract.sh /app/out/crash.mkd