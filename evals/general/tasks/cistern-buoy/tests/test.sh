#!/bin/bash
# cistern-buoy verifier.
#
# Grades four things:
#  (1) behaviour: the instruction's exact reproducer against the agent's
#      rebuilt binary must produce a 3-entry cache file with the capped
#      expiry (previously: 0 bytes); plus TWO authored hidden cases the
#      upstream test does not use (max-age one second over the two-year cap
#      with includeSubDomains; and INT32_MAX max-age) with exact expected
#      files under different fixed clocks,
#  (2) the project's own machinery: the upstream regression test for this
#      bug (tests/data/test1862, extracted from the fix commit into
#      /opt/golden, never present in the agent's tree) must pass, and the
#      existing HSTS-related tests (1 basic HTTP, 1660 + 1674 HSTS unit)
#      must stay green,
#  (3) provenance: the clone is still the pinned parent commit, the fix
#      commit is not reachable, the only tracked change allowed is the HSTS
#      cache writer, and no stray untracked files were added,
#  (4) the write-up at /app/diagnosis.md exists and names the feature.
#
# Writes 1/0 to /logs/verifier/reward.txt. The EXIT trap guarantees that a
# verifier that dies before writing still yields 0.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
# Nothing the agent left in the environment may redirect our library loading:
# the trial container is reused, so LD_PRELOAD/LD_LIBRARY_PATH could point at
# an agent-placed shim. The binary's own libtool wrapper sets what it needs.
unset LD_PRELOAD LD_LIBRARY_PATH 2>/dev/null || true

SRC=/app/src
CURL_BIN=/app/src/src/curl
PARENT_SHA=b8172ada19b1211aeed64f473b4a53e941c6fabe
FIX_SHA=08d50a791b3197a3d0a4fc2f778e243f5501c67e
FAILS=0

say_fail() {
    echo "FAIL: $*"
    FAILS=$((FAILS + 1))
}

# ---------------------------------------------------------------------------
# 0. Deliverables present.
# ---------------------------------------------------------------------------
[ -x "$CURL_BIN" ] || say_fail "curl binary missing or not executable at $CURL_BIN"
[ -f "$SRC/lib/hsts.c" ] || say_fail "source tree missing lib/hsts.c"
[ -s /app/diagnosis.md ] || say_fail "/app/diagnosis.md missing or empty"

# ---------------------------------------------------------------------------
# 1. Provenance of the tree (run before our own make, so a clean snapshot is
#    what we compare against).
# ---------------------------------------------------------------------------
head_sha=$(git -C "$SRC" rev-parse --verify HEAD^{commit} 2>/dev/null || true)
case "$head_sha" in
    "$PARENT_SHA"*) ;;
    *) say_fail "clone HEAD is not the pinned parent commit (got '$head_sha')" ;;
esac

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
    say_fail "the upstream fix commit is reachable from the clone"
fi

git -C "$SRC" status --porcelain > /tmp/cb_status.txt 2>&1 || say_fail "git status failed in $SRC"
# Tracked changes (any 2-char status that is not '?? ').
tracked=$(awk 'substr($0,1,2) != "??" {print $2}' /tmp/cb_status.txt)
if [ -n "$tracked" ]; then
    odd=$(printf '%s\n' "$tracked" | grep -vx 'lib/hsts.c' || true)
    if [ -n "$odd" ]; then
        say_fail "unexpected tracked changes: $(printf '%s' "$odd" | tr '\n' ' ')"
    fi
fi
untracked=$(awk 'substr($0,1,2) == "??" {print $2}' /tmp/cb_status.txt)
if [ -n "$untracked" ]; then
    say_fail "unexpected untracked files in tree: $(printf '%s' "$untracked" | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
# 2. Regenerate the curl binary FROM THE TREE every run, then probe it.
#
# The prebuilt src/curl is a libtool wrapper script over src/.libs/curl, and
# both are gitignored build artifacts. An agent can plant a wrapper (or a
# staged ELF) at those paths that intercepts every `curl` invocation and
# rewrites the HSTS cache files to look fixed while lib/hsts.c stays buggy;
# because git status ignores the paths, provenance alone does not catch it.
# Deleting both and relinking from the tree's objects forces whatever the
# agent left at those paths to be re-derived from the checked-in source, and
# the magic-byte + --version probes confirm a real ELF ends up there.
# ---------------------------------------------------------------------------
( cd "$SRC" && rm -f src/curl src/.libs/curl && make -j1 > /tmp/cb_make.log 2>&1 )
if [ $? -ne 0 ]; then
    say_fail "make failed to relink src/curl from the tree:"
    tail -n 15 /tmp/cb_make.log >&2
fi
if [ ! -x "$CURL_BIN" ]; then
    say_fail "make did not produce an executable $CURL_BIN"
fi
real_bin="$SRC/src/.libs/curl"
if [ ! -f "$real_bin" ]; then
    real_bin="$CURL_BIN"
fi
magic=$(head -c 4 "$real_bin" 2>/dev/null | od -An -tx1 | tr -d ' \n')
if [ "$magic" != "7f454c46" ]; then
    say_fail "src/.libs/curl is not an ELF binary (magic '$magic'): a wrapper is not a fix"
fi
if ! vout=$("$CURL_BIN" --version 2>&1 | grep -m1 '^curl '); then
    say_fail "regenerated curl does not run: $($CURL_BIN --version 2>&1 | head -n 1)"
fi
case "$vout" in
    curl*) ;;
    *) say_fail "regenerated binary is not curl: '$vout'" ;;
esac
echo "PASS [rebuild] src/curl regenerated from the tree (${vout%% *})"

# ---------------------------------------------------------------------------
# 3. Behaviour: a cache must survive an extreme max-age and record the host
#    with a two-year-capped expiry. Loopback HTTP servers, one per scenario.
# ---------------------------------------------------------------------------
start_hsts_server() { # port maxage subs
    CB_PORT="$1" CB_MAXAGE="$2" CB_SUBS="$3" python3 - <<'PY' &
import os
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        body = b'-foo-'
        self.send_response(200)
        self.send_header('Date', 'Tue, 09 Nov 2010 14:49:00 GMT')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Connection', 'close')
        hdr = 'max-age=' + os.environ['CB_MAXAGE']
        if os.environ['CB_SUBS'] == '1':
            hdr += '; includeSubDomains'
        self.send_header('Strict-Transport-Security', hdr)
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass
port = int(os.environ['CB_PORT'])
HTTPServer(('127.0.0.1', port), H).serve_forever()
PY
}

check_scenario() { # name seed_file port host subdomains curl_time
    local name=$1 seed=$2 port=$3 host=$4 subs=$5 base=$6
    local work=/tmp/cb_$name
    rm -rf "$work"; mkdir -p "$work"
    cp "$seed" "$work/hsts_in"

    ( cd "$work" && \
      CURL_HSTS_HTTP=yes CURL_TIME="$base" \
      "$CURL_BIN" -s -o /dev/null --hsts ./hsts_in \
      --resolve "$host:$port:127.0.0.1" "http://$host:$port/" ) \
      > /tmp/cb_curl_$name.out 2>&1
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        say_fail "$name: curl exited $rc (expected 0); tail:"
        tail -n 3 /tmp/cb_curl_$name.out >&2
        return
    fi

    CB_BASE="$base" CB_HOST="$host" CB_SUBS="$subs" CB_SEED="$seed" \
    CB_OUT="$work/hsts_in" python3 - <<'PY' || say_fail "$name: cache content mismatch (see above)"
import os
import sys
import time
base = int(os.environ['CB_BASE'])
host = os.environ['CB_HOST']
sub = os.environ['CB_SUBS'] == '1'
seed = open(os.environ['CB_SEED'], 'rb').read()
if not seed.endswith(b'\n'):
    seed += b'\n'
got = open(os.environ['CB_OUT'], 'rb').read()
cap = 2 * 365 * 24 * 3600
stamp = time.strftime('%Y%m%d %H:%M:%S', time.gmtime(base + cap))
entry = ('.' if sub else '') + host + ' "' + stamp + '"\n'
expected = seed + entry.encode()
if got == expected:
    print('PASS %s: %d-byte cache, capped entry %r, seeds intact' % (host, len(got), entry.strip()))
else:
    print('FAIL %s: expected %d bytes, got %d' % (host, len(expected), len(got)))
    for i, (a, b) in enumerate(zip(expected.splitlines(), got.splitlines())):
        if a != b:
            print('  line %d: expected %r got %r' % (i, a, b))
    if len(expected.splitlines()) != len(got.splitlines()):
        print('  line-count differs: expected %d got %d' % (len(expected.splitlines()), len(got.splitlines())))
    sys.exit(1)
PY
}

# (a) the exact reproducer from the instruction (extreme max-age, fixed clock).
printf '%s\n' \
'# Your HSTS cache. https://curl.se/docs/hsts.html' \
'# This file was generated by libcurl! Edit at your own risk.' \
'somehere.example "20330525 03:33:20"' \
'elsewhere.example.com "20330727 03:33:20"' > /tmp/cb_seed_repro
start_hsts_server 8891 1152921504606846976 0
cb_srv=$!
ready=0
for _ in $(seq 1 50); do
    if ( exec 3<>/dev/tcp/127.0.0.1/8891 ) 2>/dev/null; then ready=1; break; fi
    sleep 0.2
done
[ "$ready" = 1 ] || say_fail "loopback HTTP server (8891) never became ready"
check_scenario repro /tmp/cb_seed_repro 8891 this.hsts.example 0 1920582000
kill "$cb_srv" 2>/dev/null
wait "$cb_srv" 2>/dev/null

# (b) authored hidden variants of the same code path (different hosts, ports,
#     seeds, max-age values and clocks than the upstream test uses).
for casedir in /tests/hidden/*/; do
    [ -f "$casedir/seed" ] || continue
    name=$(basename "$casedir")
    case "$name" in
        case-maxage-boundary)
            # one second over the two-year cap, subdomain policy included
            start_hsts_server 8892 63072001 1
            svc=$! ; ready=0
            for _ in $(seq 1 50); do
                if ( exec 3<>/dev/tcp/127.0.0.1/8892 ) 2>/dev/null; then ready=1; break; fi
                sleep 0.2
            done
            [ "$ready" = 1 ] || say_fail "loopback HTTP server (8892) never became ready"
            check_scenario "$name" "$casedir/seed" 8892 cap-edge.example 1 1600000000
            kill "$svc" 2>/dev/null; wait "$svc" 2>/dev/null
            ;;
        case-int32-max)
            # INT32_MAX seconds: huge but representable by gmtime, so the
            # buggy build stores a wrong year-2091 date instead of the cap
            start_hsts_server 8893 2147483647 0
            svc=$! ; ready=0
            for _ in $(seq 1 50); do
                if ( exec 3<>/dev/tcp/127.0.0.1/8893 ) 2>/dev/null; then ready=1; break; fi
                sleep 0.2
            done
            [ "$ready" = 1 ] || say_fail "loopback HTTP server (8893) never became ready"
            check_scenario "$name" "$casedir/seed" 8893 int32-max.example 0 1700000000
            kill "$svc" 2>/dev/null; wait "$svc" 2>/dev/null
            ;;
        *) say_fail "unknown hidden case dir $name" ;;
    esac
done

# ---------------------------------------------------------------------------
# 4. The project's own regression test for this bug: test 1862 from the fix
#    commit, projected onto the tree by the verifier (never shipped there).
# ---------------------------------------------------------------------------
golden_ok=0
GOLDEN_SHA=348b968e27c9a1b599c23736c28b28b88f2d0b1b5aa18e86ef4a9052ec6f8565
if [ -f /opt/golden/test1862 ]; then
    gott=$(sha256sum /opt/golden/test1862 2>/dev/null | awk '{print $1}')
    if [ "$gott" != "$GOLDEN_SHA" ]; then
        echo "FAIL [golden] /opt/golden/test1862 tampered: sha256=$gott expected $GOLDEN_SHA"
        say_fail "golden test1862 integrity check failed"
    else
        cp /opt/golden/test1862 "$SRC/tests/data/test1862"
        ( cd "$SRC/tests" && ./runtests.pl -n 1862 > /tmp/cb_golden.log 2>&1 )
        grc=$?
        rm -f "$SRC/tests/data/test1862"
        if [ "$grc" -eq 0 ] && grep -q 'test 1862' /tmp/cb_golden.log && grep -qi 'reported OK: 100%' /tmp/cb_golden.log; then
            golden_ok=1
            echo "PASS [golden] runtests 1862 (HSTS with extreme max-age regression) passed"
        else
            echo "FAIL [golden] runtests 1862 did not pass (grc=$grc)"
            tail -n 25 /tmp/cb_golden.log
        fi
    fi
else
    echo "FAIL [golden] /opt/golden/test1862 missing from image"
fi
[ "$golden_ok" = 1 ] || say_fail "golden test 1862 failed"

# ---------------------------------------------------------------------------
# 5. The project's existing suite around the affected area stays green.
# ---------------------------------------------------------------------------
suite_ok=0
( cd "$SRC/tests" && ./runtests.pl -n 1 1660 1674 > /tmp/cb_suite.log 2>&1 )
src=$?
if [ "$src" -eq 0 ] \
        && grep -q 'reported OK: 100%' /tmp/cb_suite.log \
        && grep -q 'test 0001 ' /tmp/cb_suite.log \
        && grep -q 'test 1660 ' /tmp/cb_suite.log \
        && grep -q 'test 1674 ' /tmp/cb_suite.log; then
    suite_ok=1
    echo "PASS [suite] runtests 1 1660 1674 all green"
else
    echo "FAIL [suite] existing tests not all green (grc=$src)"
    tail -n 25 /tmp/cb_suite.log
fi
[ "$suite_ok" = 1 ] || say_fail "existing suite selection failed"

# ---------------------------------------------------------------------------
# 6. Diagnosis write-up sanity.
# ---------------------------------------------------------------------------
if ! grep -qi 'hsts' /app/diagnosis.md; then
    say_fail "/app/diagnosis.md does not mention the HSTS feature"
fi

# ---------------------------------------------------------------------------
# 7. Final provenance re-check: the verifier's own golden projection must not
#    leave residue, and nothing may have changed the tracked tree mid-run.
# ---------------------------------------------------------------------------
git -C "$SRC" status --porcelain > /tmp/cb_status_final.txt 2>&1
stay=$(awk 'substr($0,1,2) != "??" {print $2}' /tmp/cb_status_final.txt)
if [ -n "$stay" ]; then
    odd=$(printf '%s\n' "$stay" | grep -vx 'lib/hsts.c' || true)
    [ -n "$odd" ] && say_fail "tracked tree changed during verification: $(printf '%s' "$odd" | tr '\n' ' ')"
fi
adir=$(awk 'substr($0,1,2) == "??" {print $2}' /tmp/cb_status_final.txt)
if [ -n "$adir" ]; then
    say_fail "untracked files appeared during verification: $(printf '%s' "$adir" | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
# Verdict.
# ---------------------------------------------------------------------------
if [ "$FAILS" -eq 0 ]; then
    echo "REWARD 1: cache survives extreme max-age, golden+suite green, provenance clean"
    echo 1 > /logs/verifier/reward.txt
else
    echo "REWARD 0: $FAILS verifier failure(s)"
    echo 0 > /logs/verifier/reward.txt
fi
exit 0