#!/usr/bin/env bash
# Verifier for thwart-cinder (executes-deliverable).
#
# Executes every deliverable:
#   /app/db/start.sh            -> boots the shipped analytics cluster
#   /app/db/migrate/forward.sql -> applied, then /app/db/migrate/backward.sql,
#                                  then forward again; after every step the
#                                  table heap files are fingerprinted and must
#                                  be byte-identical to the runtime baseline
#                                  snapshot taken right after start
#   /app/queries/report.sql     -> output rows must equal the reference output
#                                  of the (fingerprinted) original.sql, and its
#                                  EXPLAIN ANALYZE execution must be >= 3x
#                                  faster than the original's, measured
#                                  back-to-back on the same host, under an
#                                  absolute ceiling
# plus three hidden month-window reports (/tests/hidden/H{1,2,3}/q.sql)
# whose EXPLAIN must use an index-based access method after a forward step and
# revert to sequential scans after a backward step.
#
# Writes /logs/verifier/reward.txt (1 = all pass, 0 = any fail) on every exit
# path.
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier
echo 0 > /logs/verifier/reward.txt

PSQLH=(psql -X -q -h 127.0.0.1 -p 5433 -U postgres -d analytics)
H1=/tests/hidden/H1/q.sql
H2=/tests/hidden/H2/q.sql
H3=/tests/hidden/H3/q.sql

# Fingerprints captured from the pristine cluster at image build time.
# The SQL anchors are deterministic row-content fingerprints, stable across
# independent image builds. The heap-file md5s are NOT baked: page-header WAL
# stamps in the tail pages are not byte-reproducible between builds (observed
# on this host), so the physical baseline is captured at runtime (gate 3) and
# the F/B/F cycle below compares against that live snapshot.
EV_SQL_ANCHOR="2000000|1|2000000|5008937440.45|d515a675a00b01ca918eab819b0d1d01|1db0bc055230fce9e83c1080bdf38838"
JY_SQL_ANCHOR="1200000|1|1200000|903119998.01|a80ce1e09dd66a0b3d6d775777461d92|e30b8dc21698f101ebe1c87324af7b1f"
ORIG_SHA256="1a9d5ae8a063b413e2ec88efc59604c6a108fefbd612ce5af03add6fb3c82a80"
REF_ROWS="2025-06|audit|222536.81
2025-06|inspection|191282.35
2025-06|repair|188946.12
2025-06|triage|194832.29
2025-06|upgrade|192181.99"

FAILED=0
fail() { echo "FAIL: $*"; FAILED=1; }

# ------------------------------------------------------------------ helpers
# sql_anchors: prints "<events-anchor>\n<journeys-anchor>" or ERR lines.
sql_anchors() {
  python3 - <<'PY'
import subprocess, sys
def q(sql):
    r = subprocess.run(['psql','-X','-q','-A','-t','-h','127.0.0.1','-p','5433',
                        '-U','postgres','-d','analytics','-c', sql],
                       capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else 'ERR'
ev = q("SELECT count(*)::text||'|'||min(id)::text||'|'||max(id)::text||'|'||"
      "sum(amount)::text||'|'||"
      "md5(string_agg(id::text, ',' ORDER BY id))||'|'||"
      "md5(string_agg(region||'|'||kind||'|'||amount::text||'|'||"
      "to_char(occurred_at,'YYYY-MM-DD HH24:MI:SS'), ';' ORDER BY id)) FROM events")
jy = q("SELECT count(*)::text||'|'||min(id)::text||'|'||max(id)::text||'|'||"
      "sum(distance_km)::text||'|'||"
      "md5(string_agg(id::text, ',' ORDER BY id))||'|'||"
      "md5(string_agg(region||'|'||kind||'|'||distance_km::text||'|'||"
      "to_char(occurred_at,'YYYY-MM-DD HH24:MI:SS'), ';' ORDER BY id)) FROM journeys")
print(ev); print(jy)
PY
}

# heap_md5s: md5 of the two fact-table heap files, "<md5ev> <md5jy>" or "ERR".
heap_md5s() {
  python3 - <<'PY'
import hashlib, os, subprocess, sys
r = subprocess.run(['psql','-X','-q','-A','-t','-h','127.0.0.1','-p','5433',
                    '-U','postgres','-d','analytics','-c',
                    "SELECT pg_relation_filepath('events'::regclass)||'|'||"
                    "pg_relation_filepath('journeys'::regclass)"],
                   capture_output=True, text=True)
if r.returncode != 0:
    print('ERR'); sys.exit(0)
ev, jy = r.stdout.strip().split('|')
def md5_of(rel):
    try:
        h = hashlib.md5()
        with open(os.path.join('/srv/pgdata', rel), 'rb') as fh:
            for chunk in iter(lambda: fh.read(1 << 20), b''):
                h.update(chunk)
        return h.hexdigest()
    except OSError:
        return 'ERR'
print(md5_of(ev), md5_of(jy))
PY
}

# explain: prints "NODES|<;separated node types>\nEXEC|<float or -1>".
#   $1 = query file, $2 = plain|analyze
# Note: EXPLAIN JSON reports ALL times in milliseconds; we normalise the
# Execution Time to seconds so the caps below (60s ceiling, 0.3s floor) mean
# what they print in the human-readable diagnostics.
explain() {
  python3 - "$1" "$2" <<'PY'
import json, subprocess, sys
qf, mode = sys.argv[1], sys.argv[2]
lines = [l for l in open(qf).read().splitlines() if not l.lstrip().startswith('--')]
sql = ' '.join(l.strip() for l in lines).strip()
opts = 'ANALYZE, TIMING, ' if mode == 'analyze' else ''
r = subprocess.run(['psql','-X','-q','-A','-t','-h','127.0.0.1','-p','5433',
                    '-U','postgres','-d','analytics','-c',
                    'EXPLAIN (%sFORMAT JSON) %s' % (opts, sql)],
                   capture_output=True, text=True)
try:
    data = json.loads(r.stdout)
    entry = data[0]
except Exception:
    print('NODES|ERR')
    print('EXEC|-1')
    sys.exit(0)
plan = entry.get('Plan', {})
nodes = []
def walk(p):
    nodes.append(p.get('Node Type', ''))
    for c in p.get('Plans', []):
        walk(c)
walk(plan)
t = entry.get('Execution Time') if mode == 'analyze' else None
print('NODES|' + ';'.join(nodes))
print('EXEC|%s' % (-1 if t is None else t / 1000.0))
PY
}

# plan_assert: $1 = explain output, $2 = want (idx|seq), $3 = label.
#   want=idx : at least one index-based node and no Seq Scan
#   want=seq : a Seq Scan and no index-based node
plan_assert() {
  python3 - "$1" "$2" "$3" <<'PY'
import sys
txt, want, label = sys.argv[1], sys.argv[2], sys.argv[3]
nodes = []
for line in txt.splitlines():
    if line.startswith('NODES|'):
        nodes = line.split('|', 1)[1].split(';')
if not nodes or nodes == ['ERR']:
    print('FAIL %s: EXPLAIN produced no plan' % label); sys.exit(1)
idx = [x for x in nodes if x in ('Index Scan', 'Index Only Scan', 'Bitmap Index Scan')]
seq = [x for x in nodes if x == 'Seq Scan']
if want == 'idx':
    if not idx or seq:
        print('FAIL %s: expected an index-based plan, got: %s' % (label, ';'.join(nodes)))
        sys.exit(1)
    print('OK   %s: plan %s' % (label, ';'.join(nodes)))
else:
    if not seq or idx:
        print('FAIL %s: expected sequential-scan plan after backward, got: %s' % (label, ';'.join(nodes)))
        sys.exit(1)
    print('OK   %s: plan %s' % (label, ';'.join(nodes)))
PY
}

# ana_assert: $1 = explain(analyze) output, $2 = label, $3 = cap seconds.
#   index-based plan AND execution time < cap
ana_assert() {
  python3 - "$1" "$2" "$3" <<'PY'
import sys
txt, label, cap = sys.argv[1], sys.argv[2], float(sys.argv[3])
nodes = []; execl = -1.0
for line in txt.splitlines():
    if line.startswith('NODES|'):
        nodes = line.split('|', 1)[1].split(';')
    elif line.startswith('EXEC|'):
        try: execl = float(line.split('|', 1)[1])
        except ValueError: execl = -1.0
if not nodes or nodes == ['ERR']:
    print('FAIL %s: EXPLAIN produced no plan' % label); sys.exit(1)
idx = [x for x in nodes if x in ('Index Scan', 'Index Only Scan', 'Bitmap Index Scan')]
seq = [x for x in nodes if x == 'Seq Scan']
if not idx or seq:
    print('FAIL %s: expected an index-based plan, got: %s' % (label, ';'.join(nodes)))
    sys.exit(1)
if execl < 0 or execl >= cap:
    print('FAIL %s: execution time %.3fs not under the %.0fs cap' % (label, execl, cap))
    sys.exit(1)
print('OK   %s: plan %s in %.3fs (cap %.0fs)' % (label, ';'.join(nodes), execl, cap))
PY
}

# rel_assert: $1 = t_orig, $2 = t_rep. report must be >= 3x faster (host-
# calibrated) and under a 60s ceiling.
rel_assert() {
  python3 - "$1" "$2" <<'PY'
import sys
t_orig, t_rep = float(sys.argv[1]), float(sys.argv[2])
cap = 60.0
thr = max(0.3, t_orig / 3.0)
if t_rep < 0:
    print('FAIL: report.sql execution time not measured'); sys.exit(1)
if t_rep < cap and t_rep <= thr:
    print('OK   report.sql %.3fs vs original %.3fs (needs <= %.3fs, cap %.0fs)'
          % (t_rep, t_orig, thr, cap))
else:
    print('FAIL: report.sql %.3fs is not fast enough against original %.3fs '
          '(needs <= %.3fs, cap %.0fs)' % (t_rep, t_orig, thr, cap))
    sys.exit(1)
PY
}

# ------------------------------------------------------------------ gate 0
# deliverables exist
[ -f /app/queries/original.sql ] || fail "fixture /app/queries/original.sql missing"
[ -x /app/db/start.sh ] || fail "deliverable /app/db/start.sh missing or not executable"
for f in /app/db/migrate/forward.sql /app/db/migrate/backward.sql /app/queries/report.sql; do
  [ -f "$f" ] || fail "deliverable $f missing"
done
for f in "$H1" "$H2" "$H3"; do
  [ -f "$f" ] || fail "hidden fixture $f missing"
done
if [ "$FAILED" = 1 ]; then exit 0; fi

# ------------------------------------------------------------------ gate 1
# the shipped production query must remain unmodified
got_sha=$(sha256sum /app/queries/original.sql | awk '{print $1}')
[ "$got_sha" = "$ORIG_SHA256" ] || fail "original.sql was modified (sha256 $got_sha)"

# ------------------------------------------------------------------ gate 2
# start postgres from the agent's deliverable script
if ! timeout 240 /app/db/start.sh; then
  fail "/app/db/start.sh did not complete"
fi
up=0
for _ in $(seq 1 90); do
  if "${PSQLH[@]}" -A -t -c 'SELECT 1' >/dev/null 2>&1; then up=1; break; fi
  sleep 1
done
[ "$up" = 1 ] || fail "postgres not accepting connections at 127.0.0.1:5433"
# the instruction promises idempotency: start.sh must also succeed while the
# cluster is already up, and must not disturb it
if [ "$up" = 1 ]; then
  if ! timeout 240 /app/db/start.sh; then
    fail "/app/db/start.sh is not idempotent (failed while the cluster was up)"
  fi
fi
if [ "$FAILED" = 1 ]; then exit 0; fi

# ------------------------------------------------------------------ gate 3
# baseline: row-content anchors must match the pristine build exactly. The
# heap files are snapshotted here and this runtime snapshot is the baseline
# the migration cycle (gates 4/6/7) must leave byte-identical; the snapshot
# is taken at trial start so it is layout-stable even though the *baked*
# byte-image of the tables is not reproducible between image builds.
ev_anchor=$(sql_anchors | sed -n '1p')
jy_anchor=$(sql_anchors | sed -n '2p')
[ "$ev_anchor" = "$EV_SQL_ANCHOR" ] || fail "events row-count/checksum anchor mismatch"
[ "$jy_anchor" = "$JY_SQL_ANCHOR" ] || fail "journeys row-count/checksum anchor mismatch"
snap=$(heap_md5s)
case "$snap" in ERR*) fail "cannot fingerprint table files";; esac
[ -n "$snap" ] || fail "no heap fingerprint captured"

# ------------------------------------------------------------------ gate 4
# forward migration, data must be untouched
if ! timeout 400 "${PSQLH[@]}" -v ON_ERROR_STOP=1 -f /app/db/migrate/forward.sql; then
  fail "forward.sql did not apply cleanly"
fi
[ "$(heap_md5s)" = "$snap" ] || fail "forward migration changed the data"
if [ "$FAILED" = 1 ]; then exit 0; fi

# ------------------------------------------------------------------ gate 5
# hidden reports must now plan through an index
for q in "$H1" "$H2" "$H3"; do
  plan_assert "$(explain "$q" plain)" idx "after-forward $(basename "$(dirname "$q")")" || FAILED=1
done
if [ "$FAILED" = 1 ]; then exit 0; fi

# ------------------------------------------------------------------ gate 6
# backward migration, data still untouched, plans must revert to seq scans
if ! timeout 400 "${PSQLH[@]}" -v ON_ERROR_STOP=1 -f /app/db/migrate/backward.sql; then
  fail "backward.sql did not apply cleanly"
fi
[ "$(heap_md5s)" = "$snap" ] || fail "backward migration changed the data"
for q in "$H1" "$H2" "$H3"; do
  plan_assert "$(explain "$q" plain)" seq "after-backward $(basename "$(dirname "$q")")" || FAILED=1
done
if [ "$FAILED" = 1 ]; then exit 0; fi

# ------------------------------------------------------------------ gate 7
# forward again (round-trip), data still untouched, index plans back
if ! timeout 400 "${PSQLH[@]}" -v ON_ERROR_STOP=1 -f /app/db/migrate/forward.sql; then
  fail "second forward.sql application failed"
fi
[ "$(heap_md5s)" = "$snap" ] || fail "second forward migration changed the data"
if [ "$FAILED" = 1 ]; then exit 0; fi

# ------------------------------------------------------------------ gate 8
# report.sql must reproduce the reference rows exactly
"${PSQLH[@]}" -A -t -F'|' -v ON_ERROR_STOP=1 -f /app/queries/report.sql > /tmp/report.out 2>/tmp/report.err
rc=$?
if [ $rc != 0 ]; then
  fail "report.sql failed to run"
else
  python3 - /tmp/report.out "$REF_ROWS" <<'PY'
import sys
got = [ln.strip() for ln in open(sys.argv[1]).read().splitlines() if ln.strip()]
want = [ln.strip() for ln in sys.argv[2].splitlines() if ln.strip()]
if got != want:
    print('FAIL: report.sql rows differ from original.sql:')
    print('  got:  %s' % got)
    print('  want: %s' % want)
    sys.exit(1)
print('OK   report.sql returns exactly the rows of original.sql')
PY
  [ $? = 0 ] || FAILED=1
fi
if [ "$FAILED" = 1 ]; then exit 0; fi

# ------------------------------------------------------------------ gate 9
# hidden reports: real execution must use the index and finish under the cap
for q in "$H1" "$H2" "$H3"; do
  ana_assert "$(explain "$q" analyze)" "exec $(basename "$(dirname "$q")")" 60 || FAILED=1
done
if [ "$FAILED" = 1 ]; then exit 0; fi

# ------------------------------------------------------------------ gate 10
# execution-time gate, calibrated to this host: report.sql >= 3x faster than
# original.sql, both EXPLAIN ANALYZE'd back-to-back, plus a 60s ceiling.
t_orig=$(explain /app/queries/original.sql analyze)
t_rep=$(explain /app/queries/report.sql analyze)
rel_assert "$(printf '%s\n' "$t_orig" | sed -n 's/^EXEC|//p')" \
          "$(printf '%s\n' "$t_rep" | sed -n 's/^EXEC|//p')" || FAILED=1
# report.sql is held to the same access-method standard as the hidden reports:
# its plan must read the events table through an index. This rules out a
# hardcoded constant that returns the reference rows without querying the
# warehouse.
if [ "$FAILED" = 0 ]; then
  plan_assert "$t_rep" idx "exec /app/queries/report.sql" || FAILED=1
fi

# ------------------------------------------------------------------ verdict
if [ "$FAILED" = 0 ]; then
  echo "ALL CHECKS PASSED"
  echo 1 > /logs/verifier/reward.txt
else
  echo 0 > /logs/verifier/reward.txt
fi
exit 0