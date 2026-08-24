#!/bin/bash
# Verifier for item-070-main. Re-runs all objective checks from a neutral dir.
mkdir -p /logs/verifier

reward=0
pct=0.0
agent_pct=-1.0

# --- 1+2. PATH + behavior probes (neutral cwd)
cd /tmp
PATH_OK=0
BEHAVIOR_OK=0
if command -v sqlite3 >/dev/null 2>&1; then
  PATH_OK=1
  if python3 - <<'PYEOF'
import subprocess
def run(q):
    return subprocess.run(['sqlite3',':memory:',q], capture_output=True, text=True)
v = run("select sqlite_version();").stdout.strip()
assert v == '3.46.1', v
j = run("select json_extract('{\"a\":7}','$.a');").stdout.strip()
assert j == '7', j
f = run("CREATE VIRTUAL TABLE t USING fts5(c); INSERT INTO t VALUES ('one'),('two'); SELECT count(*) FROM t WHERE t MATCH 'one OR two';").stdout.strip()
assert f == '2', f
m = run("select round(sin(0.0),4), round(cos(0.0),4);").stdout.strip()
assert m == '0.0|1.0', m
PYEOF
then
    BEHAVIOR_OK=1
  fi
fi

# --- 3. coverage: re-run gcov, require >= 5%
BUILD=/app/src/sqlite-autoconf-3460100
GCOV_OK=0
if [ -d "$BUILD" ] && [ -f "$BUILD/sqlite3-sqlite3.gcda" ] && command -v gcov >/dev/null 2>&1; then
  if (cd "$BUILD" && gcov -n -o sqlite3-sqlite3.o sqlite3.c > /tmp/gcov_verify.txt 2>&1); then
    LINE=$(grep -oE "Lines executed:[0-9.]+% of [0-9]+" /tmp/gcov_verify.txt | head -1)
    if [ -n "$LINE" ]; then
      pct=$(echo "$LINE" | sed -E 's/Lines executed:([0-9.]+)% of ([0-9]+)/\1/')
      if python3 - "$pct" <<'PYEOF'
import sys
pct = float(sys.argv[1])
sys.exit(0 if pct >= 5.0 else 1)
PYEOF
then
        GCOV_OK=1
      fi
    fi
  fi
fi

# --- 4. agent-recorded coverage vs report.json / coverage-summary.txt
RECORDED_OK=0
if [ -f /app/artifacts/report.json ]; then
  if python3 - <<'PYEOF'
import json, re
rep = json.load(open('/app/artifacts/report.json'))
assert rep.get('sqlite_version') == '3.46.1'
assert rep.get('build_dir') == '/app/src/sqlite-autoconf-3460100'
assert rep.get('configure_command') == './configure --prefix=/usr/local --disable-shared --enable-static'
cflags = rep.get('cflags', '')
assert '--coverage' in cflags and 'SQLITE_ENABLE_FTS5' in cflags
beh = rep.get('behavior_checks', {})
assert all(beh.get(k) is True for k in ('version_matches','json_ok','fts5_ok','math_ok'))
assert rep.get('path_install_ok') is True
agent_pct = float(rep['gcov_lines_executed_pct'])
agent_tot = int(rep['gcov_total_lines'])
summ = open('/app/artifacts/coverage-summary.txt').read()
m = re.search(r'Lines executed:([0-9.]+)% of ([0-9]+)', summ)
assert m, 'summary line missing'
s_pct, s_tot = float(m.group(1)), int(m.group(2))
assert abs(s_pct - agent_pct) < 0.05
assert s_tot == agent_tot
open('/tmp/agent_pct.txt','w').write(repr(agent_pct))
PYEOF
then
    if python3 - "$pct" <<'PYEOF'
import sys, os
verified_pct = float(sys.argv[1])
agent_pct = float(open('/tmp/agent_pct.txt').read().strip())
assert abs(verified_pct - agent_pct) <= 3.0, (verified_pct, agent_pct)
PYEOF
    then
      RECORDED_OK=1
    fi
  fi
fi

# --- 5. vendor tarball sha vs recorded value
SHA_OK=0
if [ -f /app/src/sqlite-autoconf-3460100.tar.gz ] && [ -f /app/artifacts/report.json ]; then
  if python3 - <<'PYEOF'
import hashlib, json
h = hashlib.sha256(open('/app/src/sqlite-autoconf-3460100.tar.gz','rb').read()).hexdigest()
rep = json.load(open('/app/artifacts/report.json'))
assert rep.get('vendor_sha256') == h
PYEOF
then
    SHA_OK=1
  fi
fi

if [ "$PATH_OK" = "1" ] && [ "$BEHAVIOR_OK" = "1" ] && [ "$GCOV_OK" = "1" ] \
   && [ "$RECORDED_OK" = "1" ] && [ "$SHA_OK" = "1" ]; then
  reward=1
fi

echo "$reward" > /logs/verifier/reward.txt