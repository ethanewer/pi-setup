#!/bin/bash
# calm-canyon oracle: performs the real work that agents must also do, with
# literal /app paths, then runs every program it builds. Never reads /tests.
set -euo pipefail
export HOME=/root ELAN_HOME=/root/.elan
export PATH=/root/.elan/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# ---------------------------------------------------------------------------
# Deliverable 1: the generic release fetch+extract tool.
# ---------------------------------------------------------------------------
cat > /app/fetch_src.sh <<'T'
#!/bin/bash
# fetch_src.sh <mirror_url> <dest_dir>
#
# Restore a hydrawatch source release INTACT. The mirror root publishes:
#   current.txt       -> the release archive name to fetch
#   checksum.sha256   -> "<sha256>  <archive>" line for that archive
#   <archive-name>    -> the packed source tree
#
# Guarantees:
#   * the archive SHA-256 must match the one recorded in checksum.sha256,
#     otherwise the tool refuses (non-zero) and leaves <dest_dir>/ untouched;
#   * after extraction the tree must reproduce exactly the embedded
#     MANIFEST.json (present in the release); any missing / extra / modified
#     file is a hard failure and <dest_dir> is removed;
#   * the distro metadata shard (debian/control) is required.
set -euo pipefail
mirror="$1"
dest="$2"
name=$(curl -fsS "$mirror/current.txt" | tr -d "\r\n ")
[ -n "$name" ] || { echo "fetch: current.txt empty"; exit 2; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsS -o "$tmp/rel.tgz" "$mirror/$name"
curl -fsS -o "$tmp/ck.sha"  "$mirror/checksum.sha256"
exp=$(awk -v n="$name" '$2==n {print $1; exit}' "$tmp/ck.sha")
[ -n "$exp" ] || { echo "fetch: no checksum for $name"; exit 3; }
got=$(sha256sum "$tmp/rel.tgz" | awk '{print $1}')
if [ "$got" != "$exp" ]; then
  echo "fetch: checksum mismatch for $name ($got != $exp); refusing"
  exit 3
fi
rm -rf "$dest" && mkdir -p "$dest"
tar -xzf "$tmp/rel.tgz" -C "$dest"
if ! python3 "$dest/bin/verify_extract.py" "$dest"; then
  echo "fetch: extract integrity check failed"
  rm -rf "$dest"
  exit 5
fi
echo "fetch_src: restored $name intact -> $dest"
T
chmod +x /app/fetch_src.sh

# ---------------------------------------------------------------------------
# Step 1: serve the visible source store and fetch+extract the release intact.
# ---------------------------------------------------------------------------
mkdir -p /app/flink_scoped_build
cd /app/payload
nohup python3 -m http.server 8811 --bind 127.0.0.1 >/app/httpd.log 2>&1 &
sleep 1
bash /app/fetch_src.sh http://127.0.0.1:8811 /app/src

# ---------------------------------------------------------------------------
# Step 2: apply the gauge fix, then the scoped Maven rebuild.
# ---------------------------------------------------------------------------
python3 - <<'PY'
import re
p = "/app/src/src/main/java/io/hydra/watch/MetricsEngine.java"
s = open(p).read()
pat = re.compile(
    r"\s*s \+= d;\n[ \t]*if \(d < 0\) \{\n[ \t]*s \+= 7;[^\n]*\n[ \t]*\}\n",
    re.M)
s2, n = pat.subn("\ns += d;\n", s)
assert n == 1, "expected exactly one penalty term, found %d" % n
assert "s += 7" not in s2
assert s2 != s
open(p, "w").write(s2)
print("patched gauge: penalized live -> pure net flux")
PY

cd /app/src
mvn -B package > /app/build.log 2>&1
grep -q "BUILD SUCCESS" /app/build.log
test -s /app/build.log
test -f target/hydrawatch.jar
echo "maven rebuild ok (build.log written)"

# ---------------------------------------------------------------------------
# Step 3: ship the rebuilt distribution into /app/flink_scoped_build.
# ---------------------------------------------------------------------------
mkdir -p /app/flink_scoped_build
cp target/hydrawatch.jar          /app/flink_scoped_build/hydrawatch.jar
cp runtime/live.json              /app/flink_scoped_build/live.json
cat > /app/flink_scoped_build/start.sh <<'S'
#!/bin/bash
set -euo pipefail
export HYDRA_LIVE=/app/flink_scoped_build/live.json
export HYDRA_PORT="${HYDRA_PORT:-8790}"
cd /app/flink_scoped_build
exec java -jar /app/flink_scoped_build/hydrawatch.jar
S
chmod +x /app/flink_scoped_build/start.sh

# ---------------------------------------------------------------------------
# Step 4: run the patched service on the expected local port (8790).
# ---------------------------------------------------------------------------
export HYDRA_LIVE=/app/flink_scoped_build/live.json HYDRA_PORT=8790
nohup java -jar /app/flink_scoped_build/hydrawatch.jar \
  > /app/flink_scoped_build/service.log 2>&1 &
for _ in $(seq 1 40); do
  curl -fsS http://127.0.0.1:8790/api/v1/health >/dev/null 2>&1 && break
  sleep 0.25
done
{
  echo "health: $(curl -s http://127.0.0.1:8790/api/v1/health)"
  echo "upload_abc: $(curl -s -d abc http://127.0.0.1:8790/api/v1/upload)"
  echo "live: $(curl -s http://127.0.0.1:8790/api/v1/metric/live)"
} > /app/behavior_check.log
test -s /app/behavior_check.log

# ---------------------------------------------------------------------------
# Step 5: scaffold the Lean lake project that pulls the bundled math library.
# ---------------------------------------------------------------------------
mkdir -p /app/lake_project/Basin
cat > /app/lake_project/lakefile.lean <<'L'
import Lake
open Lake DSL

package basin
require "math" from "../mlib"

lean_lib Basin
L
printf 'import Basin.Probe\n' > /app/lake_project/Basin.lean
cat > /app/lake_project/Basin/Probe.lean <<'L'
import Math.Sum

theorem basin_double (n m : Nat) : Math.Sum.doubleSum n m = 2 * n + m := by
  exact Math.Sum.doubleSum_eq n m

theorem basin_comm (a b : Nat) : a + b = b + a := Math.Sum.add_comm_own a b

theorem basin_sq : 0 < 9 * 9 := by
  exact Math.Sum.sq_pos 9 (by decide)
L
cd /app/lake_project
lake build Basin > /app/lake_build.log 2>&1
test -f ./.lake/build/lib/lean/Basin/Probe.olean
cp ./.lake/build/lib/lean/Basin/Probe.olean /app/math_check.olean
test -s /app/math_check.olean
echo "lake build ok (math_check.olean written)"

# ---------------------------------------------------------------------------
# Step 6: generate the two python binding modules from /app/telemetry.proto.
# ---------------------------------------------------------------------------
cat > /app/gen_proto.py <<'G'
#!/usr/bin/env python3
"""gen_proto.py <proto_file> <out_dir>

Run grpc_tools.protoc over <proto_file> to emit the two python binding modules
(*_pb2.py and *_pb2_grpc.py) into <out_dir>. Exits 0 only when both modules
are produced. The output directory is created if needed.
"""
import os
import sys


def main():
    if len(sys.argv) != 3:
        print("usage: gen_proto.py <proto> <out_dir>", file=sys.stderr)
        return 2
    proto = os.path.abspath(sys.argv[1])
    out = sys.argv[2]
    os.makedirs(out, exist_ok=True)
    from grpc_tools import protoc

    inc = os.path.dirname(proto)
    rc = protoc.main([
        "grpc_tools.protoc",
        "-I" + inc,
        "--python_out=" + out,
        "--grpc_python_out=" + out,
        proto,
    ])
    stem = os.path.splitext(os.path.basename(proto))[0]
    need = [stem + "_pb2.py", stem + "_pb2_grpc.py"]
    if not all(os.path.exists(os.path.join(out, n)) for n in need):
        print("gen_proto: missing generated module(s)", file=sys.stderr)
        return 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
G
chmod +x /app/gen_proto.py
python3 /app/gen_proto.py /app/telemetry.proto /app/gen
test -f /app/gen/telemetry_pb2.py
test -f /app/gen/telemetry_pb2_grpc.py

# ---------------------------------------------------------------------------
# Step 7: a small client that consumes the generated bindings.
# ---------------------------------------------------------------------------
cat > /app/proto_client.py <<'P'
#!/usr/bin/env python3
"""Small client consuming the generated bindings in /app/gen.

Performs a serialization/reparse round-trip and reports it on stdout.
"""
import sys

sys.path.insert(0, "/app/gen")
import telemetry_pb2
import telemetry_pb2_grpc  # noqa: F401  (ensures the rpc module imports)


def main():
    s = telemetry_pb2.Sample(id=7, label="fjord", value=1.25)
    wire = s.SerializeToString()
    back = telemetry_pb2.Sample()
    back.ParseFromString(wire)
    if not (back == s and back.id == 7 and back.label == "fjord"):
        print("proto client: round-trip FAIL")
        return 1
    print("proto round-trip OK (id=%d label=%s)" % (back.id, back.label))
    return 0


if __name__ == "__main__":
    sys.exit(main())
P
chmod +x /app/proto_client.py
python3 /app/proto_client.py

echo "oracle done: all deliverables produced"