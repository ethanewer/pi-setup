#!/bin/bash
# calm-canyon verifier. Runs as root after the agent finishes; /tests is mounted
# read-only. Writes the numeric reward (0 or 1) to /logs/verifier/reward.txt.
#
# It EXECUTES the declared deliverables on hidden input:
#   * /app/fetch_src.sh   -> healthy, bad-checksum and tampered hidden mirrors
#   * /app/src            -> offline scoped Maven rebuild, then runs the rebuilt jar
#   * /app/flink_scoped_build -> runs the shipped jar, checks REST contract +
#                                pure net-flux gauge
#   * /app/lake_project   -> lake build against a hidden injected theorem that
#                            depends on the pulled math library
#   * /app/gen_proto.py   -> regenerate bindings from a hidden .proto, compile+round-trip
#   * /app/proto_client.py -> round-trip over /app/gen bindings
set -uo pipefail

export PATH=/root/.elan/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root

mkdir -p /logs/verifier
ERR=/logs/verifier/errors.log
: > "$ERR"
reward=1
fail(){ echo "VERIFY_FAIL: $1" >> "$ERR"; reward=0; }
ok(){ :; }

echo "== calm-canyon verifier: $0 =="

# ---------------------------------------------------------------------------
# Deliverable 1: /app/fetch_src.sh against three hidden mirrors
# ---------------------------------------------------------------------------
test -x /app/fetch_src.sh || { fail "fetch_src.sh missing or not executable"; ok; }

# minimal guard so the rest can safely reference it
if ! test -x /app/fetch_src.sh; then
  reward=0
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

python3 -m http.server 8813 --bind 127.0.0.1 --directory /tests/hidden/fetch \
  >/tmp/ver_hsrv.log 2>&1 &
HSP=$!
sleep 1

# H1: healthy hidden mirror rel2029.52.1 must fetch intact.
if test -x /app/fetch_src.sh; then
  rm -rf /app/_h1
  rc1=1
  bash /app/fetch_src.sh http://127.0.0.1:8813/rel2029.52.1 /app/_h1 && rc1=0
  if [ "$rc1" -ne 0 ] || [ ! -d /app/_h1 ]; then
    fail "healthy mirror fetch failed (rc=$rc1)"
  else
    if python3 /app/_h1/bin/verify_extract.py /app/_h1 && \
       test -f /app/_h1/debian/control && \
       test -f /app/_h1/pom.xml && \
       test -f /app/_h1/src/main/java/io/hydra/watch/HydraREST.java; then
      ok "H1: healthy hidden release restored intact"
    else
      fail "H1: hidden tree not intact (verify_extract failed)"
    fi
  fi
fi

# H2: bad-checksum mirror -> must refuse, destination must be absent.
if test -x /app/fetch_src.sh; then
  rm -rf /app/_h2
  if bash /app/fetch_src.sh http://127.0.0.1:8813/rel2029.41.7-bad /app/_h2 2>/dev/null; then
    fail "H2: fetch accepted a bad-checksum mirror (must not)"
  else
    if [ -e /app/_h2 ]; then
      fail "H2: destination left behind after refusing bad checksum"
    else
      ok "H2: bad-checksum mirror correctly refused, dest untouched"
    fi
  fi
fi

# H3: tampered tree (valid checksum, internal manifest mismatch) -> refuse.
if test -f "/app/fetch_src.sh"; then
  rm -rf /app/_h3
  if bash /app/fetch_src.sh http://127.0.0.1:8813/rel2029.07.3-tampered /app/_h3 2>/dev/null; then
    fail "H3: fetch accepted a tampered tree"
  else
    if [ -e /app/_h3 ]; then
      fail "H3: destination left behind after refusing tampered tree"
    else
      ok "H3: tampered tree rejected, dest untouched"
    fi
  fi
fi
kill "$HSP" 2>/dev/null || true

# The visible source deliverable must exist as a buildable tree.
if [ -f /app/src/pom.xml ] && [ -f /app/src/bin/verify_extract.py ]; then
  ok "source tree /app/src present (pom+verify present)"
else
  fail "/app/src missing required files (pom.xml / bin/verify_extract.py)"
fi

# ---------------------------------------------------------------------------
# Deliverable 2: scoped Maven rebuild + distribution
# ---------------------------------------------------------------------------
if [ -s /app/build.log ] && grep -q "BUILD SUCCESS" /app/build.log; then
  ok "build.log complete with BUILD SUCCESS"
else
  fail "build.log missing / no BUILD SUCCESS"
fi

# Execute the source tree: rerun the scoped Maven rebuild (offline-ish; the
# agent already resolved the plugins, so ~/.m2 is warm) and confirm it still
# produces the jar.
if [ -f /app/src/pom.xml ]; then
  rm -f /app/src/target/hydrawatch.jar
  if ( cd /app/src && mvn -B -o package >/tmp/verif_mvn.log 2>&1 ) && \
     [ -f /app/src/target/hydrawatch.jar ]; then
    ok "scoped Maven rebuild of /app/src produced target/hydrawatch.jar"
  else
    # allow online fallback (network variance)
    if ( cd /app/src && mvn -B package >/tmp/verif_mvn.log 2>&1 ) && \
       [ -f /app/src/target/hydrawatch.jar ]; then
      ok "scoped Maven rebuild of /app/src succeeded (online path)"
    else
      fail "scoped Maven rebuild of /app/src failed"
    fi
  fi
fi

# Distribution deliverable present.
if [ -f /app/flink_scoped_build/hydrawatch.jar ] && \
   [ -f /app/flink_scoped_build/live.json ]; then
  ok "distribution /app/flink_scoped_build present"
else
  fail "/app/flink_scoped_build missing hydrawatch.jar or live.json"
fi

# Initialize service (shipped jar) and assert REST contract + pure net-flux gauge.
SHIP=/app/flink_scoped_build
HLIVE="$SHIP/live.json"
if [ -f "$SHIP/hydrawatch.jar" ]; then
  HYDRA_LIVE="$HLIVE" HYDRA_PORT=8796 java -jar "$SHIP/hydrawatch.jar" \
    >/tmp/verif_svc.log 2>&1 &
  JPID=$!
  up=""
  for _ in $(seq 1 40); do
    if curl -fsS http://127.0.0.1:8796/api/v1/health >/dev/null 2>&1; then up=1; break; fi
    sleep 0.3
  done
  if [ -z "$up" ]; then
    fail "shipped distribution service did not start"
  else
    h=$(curl -s http://127.0.0.1:8796/api/v1/health)
    [ "$h" = '{"status":"ok"}' ] && ok "health unchanged" || fail "health shape changed: $h"
    u=$(curl -s -d 'payload' http://127.0.0.1:8796/api/v1/upload)
    [ "$u" = '{"accepted":true,"bytes":7}' ] && ok "upload accepted (bytes=7)" || fail "upload changed: $u"
    l=$(curl -s http://127.0.0.1:8796/api/v1/metric/live)
    exp=$(python3 - <<PY
import re
s=open("$HLIVE").read()
m=re.findall(r"-?\d+", s[s.find("["):s.rfind("]")])
print(sum(map(int,m)))
PY
)
    got=$(echo "$l" | sed -n 's/.*"live"[[:space:]]*:[[:space:]]*\(-\{0,1\}[0-9]*\).*/\1/p')
    if [ "$got" = "$exp" ]; then
      ok "gauge is pure net flux (live=$got == expected $exp)"
    else
      fail "gauge wrong: got=$got expected=$exp (penalty term present?)"
    fi
  fi
  kill "$JPID" 2>/dev/null || true
fi

# behavior_check.log deliverable.
if [ -s /app/behavior_check.log ]; then ok "behavior_check.log written"; else fail "behavior_check.log missing or empty"; fi

# ---------------------------------------------------------------------------
# Deliverable 3: Lean lake project pulling the math library
# ---------------------------------------------------------------------------
if [ -f /app/lake_project/lakefile.lean ]; then ok "lake_project/lakefile.lean present"; else fail "lake_project missing lakefile.lean"; fi
if [ -s /app/math_check.olean ]; then ok "math_check.olean present/nonempty"; else fail "math_check.olean missing or empty"; fi

# Inject a hidden theorem that depends ONLY on the bundled math library, then
# re-run lake build. Discover the project's own library dir from built oleans.
if [ -f /app/lake_project/lakefile.lean ]; then
  cd /app/lake_project
  libdir=$(ls .lake/build/lib/lean/ 2>/dev/null | grep -v '^\.' | head -1)
  if [ -n "$libdir" ]; then
    # Confirm the clean scaffold still compiles, then inject the hidden theorem
    # (depends ONLY on the bundled math library) and build the module by name.
    if lake build "$libdir" >/tmp/verif_lake_base.log 2>&1; then
      ok "base lake build ok ($libdir)"
    else
      fail "base lake build failed ($libdir)"
    fi
    cp /tests/hidden/lean/HiddenProof.lean "./$libdir/HiddenProof.lean"
    if lake build "$libdir.HiddenProof" >/tmp/verif_lake.log 2>&1 && \
       [ -f ".lake/build/lib/lean/$libdir/HiddenProof.olean" ]; then
      ok "hidden math-theorem compiled via pulled math dependency ($libdir.HiddenProof)"
    else
      fail "lake hidden theorem failed to build (math dep unresolved)"
    fi
  else
    fail "could not discover lake library dir under .lake/build/lib/lean"
  fi
  cd /
fi

# ---------------------------------------------------------------------------
# Deliverable 4: Python binding generator + client
# ---------------------------------------------------------------------------
if [ -f /app/gen_proto.py ]; then ok "gen_proto.py present"; else fail "gen_proto.py missing"; fi
if [ -f /app/gen/telemetry_pb2.py ] && [ -f /app/gen/telemetry_pb2_grpc.py ]; then ok "/app/gen bindings present"; else fail "/app/gen missing pb2 modules"; fi

if [ -f /app/gen_proto.py ]; then
  # (a) regenerate the visible bindings into a fresh dir and import them.
  rm -rf /app/_gen_v && mkdir -p /app/_gen_v
  if python3 /app/gen_proto.py /app/telemetry.proto /app/_gen_v && \
     python3 - <<PY
import sys; sys.path.insert(0,"/app/_gen_v")
import telemetry_pb2, telemetry_pb2_grpc
s=telemetry_pb2.Sample(id=9,label="harbor",value=2.5)
w=s.SerializeToString(); b=telemetry_pb2.Sample(); b.ParseFromString(w)
assert b==s and b.id==9 and b.label=="harbor", "round trip mismatch"
print("visible rebind ok")
PY
  then
    ok "visible proto rebind + round-trip ok"
  else
    fail "visible proto rebind or import failed"
  fi

  # (b) generate bindings from a hidden .proto and round-trip.
  rm -rf /app/gen_hidden && mkdir -p /app/gen_hidden
  if python3 /app/gen_proto.py /tests/hidden/proto/ingest.proto /app/gen_hidden && \
     test -f /app/gen_hidden/ingest_pb2.py && \
     test -f /app/gen_hidden/ingest_pb2_grpc.py && \
     python3 - <<PY
import sys; sys.path.insert(0,"/app/gen_hidden")
import ingest_pb2, ingest_pb2_grpc
r=ingest_pb2.Reading(ts=1,node="n1",flux=-7.5,healthy=1)
w=r.SerializeToString(); b=ingest_pb2.Reading(); b.ParseFromString(w)
assert b==r and b.node=="n1" and abs(b.flux-(-7.5))<1e-9
print("hidden rebind ok")
PY
  then
    ok "hidden proto bindings + round-trip ok"
  else
    fail "hidden proto bindings or round-trip failed"
  fi
fi

# client deliverable.
if test -f /app/proto_client.py && python3 /app/proto_client.py >/tmp/verif_client.log 2>&1; then
  ok "proto_client round-trip ok"
else
  fail "proto_client.py failed to run correctly"
fi

# ---------------------------------------------------------------------------
echo "reward=$reward"
echo "$reward" > /logs/verifier/reward.txt
sort "$ERR" | sed 's/^/  /'
exit 0