#!/bin/bash
# bracket-bell verifier.
#
# Grades three things:
#  (1) behaviour: /app/src/src/curl survives a comment-only / empty .netrc
#      file and completes the request anonymously (CLI repro + 3 authored
#      hidden variants over a loopback HTTP server),
#  (2) the project's own machinery: the upstream regression test for this
#      bug (tests/data/test2429, extracted from the fix commit into
#      /opt/golden, never present in the agent's tree) must pass, and the
#      existing netrc-relevant tests (1304 unit, 2005, 2309) plus a basic
#      HTTP test (1) must stay green,
#  (3) provenance: the clone is still the pinned parent commit, the fix
#      commit is not reachable, the tracked change allowed is the
#      credential-file parser and there must be at least one, and no stray
#      untracked files were added.
#
# Anti-fake: the verifier wipes the build and rebuilds from the current
# source tree with `make clean && make` before any behavioural check. That
# defeats every scheme that leaves the source buggy while making the graded
# binary behave (swapped binaries, swapped libtool wrappers, replaced object
# files, future-mtime objects, wrapper scripts standing in for the binary).
# The graded binary is therefore genuinely derived from the tree the agent
# hands back. The golden test extracted into /opt/golden at build time is
# pinned by checksum so a forked copy cannot replace the real regression
# test.
#
# Writes 1/0 to /logs/verifier/reward.txt. The EXIT trap guarantees that a
# verifier that dies before writing still yields 0.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

SRC=/app/src
CURL_BIN=/app/src/src/curl
PARENT_SHA=fd8c409d6ab7367051d04646a31e976e3db0c6ed
FIX_SHA=1143bc9ac6912743a0fef78d5ac81426b172976d
# sha256 of the upstream regression test as extracted at image build time
# (tests/data/test2429 from the fix commit).
GOLDEN_SHA256=9df214e8bd267a989abbd6efce65e9e15997a9b46cdb30936fe98c78f1e63774
PORT=8890
FAILS=0

say_fail() {
    echo "FAIL: $*"
    FAILS=$((FAILS + 1))
}

# ---------------------------------------------------------------------------
# 0. Deliverables present.
# ---------------------------------------------------------------------------
[ -x "$CURL_BIN" ] || say_fail "curl binary missing or not executable at $CURL_BIN"
[ -f "$SRC/lib/netrc.c" ] || say_fail "source tree missing lib/netrc.c"
[ -s /app/diagnosis.md ] || say_fail "/app/diagnosis.md missing or empty"

# ---------------------------------------------------------------------------
# 1. Provenance of the tree (run before our own rebuild, so a clean snapshot
#    is what we compare against).
# ---------------------------------------------------------------------------
head_sha=$(git -C "$SRC" rev-parse --verify HEAD^{commit} 2>/dev/null || true)
case "$head_sha" in
    "$PARENT_SHA"*) ;;
    *) say_fail "clone HEAD is not the pinned parent commit (got '$head_sha')" ;;
esac

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
    say_fail "the upstream fix commit is reachable from the clone"
fi

git -C "$SRC" status --porcelain > /tmp/bb_status.txt 2>&1 || say_fail "git status failed in $SRC"
# Tracked changes (any 2-char status that is not '?? ').
tracked=$(awk 'substr($0,1,2) != "??" {print $2}' /tmp/bb_status.txt)
if [ -z "$tracked" ]; then
    say_fail "no tracked source change in the tree: the fix must live in the source, not in a swapped binary"
fi
odd=$(printf '%s\n' "$tracked" | grep -vx 'lib/netrc.c' || true)
if [ -n "$odd" ]; then
    say_fail "unexpected tracked changes: $(printf '%s' "$odd" | tr '\n' ' ')"
fi
untracked=$(awk 'substr($0,1,2) == "??" {print $2}' /tmp/bb_status.txt)
if [ -n "$untracked" ]; then
    say_fail "unexpected untracked files in tree: $(printf '%s' "$untracked" | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
# 2. Wipe the build and rebuild from the current tree, so /app/src/src/curl
#    is genuinely the project's own build of the agent's source. This is
#    deliberate: it defeats binary swaps, wrapper scripts and object-file
#    replacements that would otherwise make an unfixed tree pass. The clean
#    rebuild takes ~2 minutes at 1 CPU.
# ---------------------------------------------------------------------------
if ! ( cd "$SRC" && make clean > /tmp/bb_clean.log 2>&1 \
        && make -j1 > /tmp/bb_make.log 2>&1 \
        && make -C tests all > /tmp/bb_tests.log 2>&1 ); then
    say_fail "clean rebuild from source failed:"
    tail -n 15 /tmp/bb_make.log 2>&1 >&2 || true
    tail -n 15 /tmp/bb_clean.log >&2 || true
    tail -n 15 /tmp/bb_tests.log >&2 || true
fi

[ -x "$CURL_BIN" ] || say_fail "curl binary missing after rebuild"
case "$(file -b "$SRC/src/.libs/curl" 2>/dev/null)" in
    ELF*) ;;
    *) say_fail "src/.libs/curl is not the ELF binary the build produced" ;;
esac

# ---------------------------------------------------------------------------
# 3. Behaviour: comment-only / empty credentials file must not crash.
#    Local throwaway HTTP server for the CLI checks.
# ---------------------------------------------------------------------------
python3 - "$PORT" <<'PY' &
import http.server
import sys

port = int(sys.argv[1])

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = b'-foo-'
        self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass

http.server.HTTPServer(('127.0.0.1', port), H).serve_forever()
PY
bb_srv=$!
ready=0
for _ in $(seq 1 50); do
    if ( exec 3<>/dev/tcp/127.0.0.1/$PORT ) 2>/dev/null; then ready=1; break; fi
    sleep 0.2
done
if [ "$ready" != 1 ]; then
    say_fail "loopback HTTP server never became ready"
fi

# (a) the exact reproducer from the instruction.
printf '# only a comment line' > /tmp/bb_repro.netrc
set +e
"$CURL_BIN" --netrc --netrc-file /tmp/bb_repro.netrc "http://127.0.0.1:$PORT/" > /tmp/bb_repro.out 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then
    say_fail "CLI reproducer: curl exited $rc (expected 0); output tail:"
    tail -n 3 /tmp/bb_repro.out >&2
fi
grep -q -- '-foo-' /tmp/bb_repro.out || say_fail "CLI reproducer: server body not received"
grep -qi 'segmentation' /tmp/bb_repro.out && say_fail "CLI reproducer: still segfaulting"

# (b) authored hidden variants of the same code path.
for casedir in /tests/hidden/*/; do
    [ -f "$casedir/netrc" ] || continue
    name=$(basename "$casedir")
    set +e
    "$CURL_BIN" --netrc --netrc-file "$casedir/netrc" "http://127.0.0.1:$PORT/" > /tmp/bb_hidden.out 2>&1
    rc=$?
    if [ "$rc" -ne 0 ]; then
        say_fail "hidden/$name: curl exited $rc (expected 0)"
        tail -n 3 /tmp/bb_hidden.out >&2
    fi
    grep -q -- '-foo-' /tmp/bb_hidden.out || say_fail "hidden/$name: server body not received"
    grep -qi 'segmentation' /tmp/bb_hidden.out && say_fail "hidden/$name: still segfaulting"
done

kill "$bb_srv" 2>/dev/null
wait "$bb_srv" 2>/dev/null

# ---------------------------------------------------------------------------
# 4. The project's own regression test for this bug: test 2429 from the fix
#    commit, projected onto the tree by the verifier (never shipped there).
#    The copy in /opt/golden is checksum-pinned.
# ---------------------------------------------------------------------------
golden_ok=0
if [ -f /opt/golden/test2429 ]; then
    if ! ( echo "$GOLDEN_SHA256  /opt/golden/test2429" | sha256sum -c - > /dev/null 2>&1 ); then
        echo "FAIL [golden] /opt/golden/test2429 checksum does not match the upstream regression test"
    else
        cp /opt/golden/test2429 "$SRC/tests/data/test2429"
        ( cd "$SRC/tests" && ./runtests.pl -n 2429 > /tmp/bb_golden.log 2>&1 )
        grc=$?
        rm -f "$SRC/tests/data/test2429"
        if [ "$grc" -eq 0 ] && grep -q '2429' /tmp/bb_golden.log && grep -qi 'reported OK: 100%' /tmp/bb_golden.log; then
            golden_ok=1
            echo "PASS [golden] runtests 2429 (comment-only .netrc regression) passed"
        else
            echo "FAIL [golden] runtests 2429 did not pass (grc=$grc)"
            tail -n 25 /tmp/bb_golden.log
        fi
    fi
else
    echo "FAIL [golden] /opt/golden/test2429 missing from image"
fi
[ "$golden_ok" = 1 ] || say_fail "golden test 2429 failed"

# ---------------------------------------------------------------------------
# 5. The project's existing suite around the affected area stays green.
# ---------------------------------------------------------------------------
suite_ok=0
( cd "$SRC/tests" && ./runtests.pl -n 1 2005 2309 1304 > /tmp/bb_suite.log 2>&1 )
src=$?
if [ "$src" -eq 0 ] \
        && grep -q 'reported OK: 100%' /tmp/bb_suite.log \
        && grep -q 'test 0001 \[HTTP GET\]' /tmp/bb_suite.log \
        && grep -q 'test 2005 \[netrc match' /tmp/bb_suite.log \
        && grep -q 'test 2309 \[HTTP with .netrc' /tmp/bb_suite.log \
        && grep -q 'test 1304 \[netrc parsing unit tests\]' /tmp/bb_suite.log; then
    suite_ok=1
    echo "PASS [suite] runtests 1 2005 2309 1304 all green"
else
    echo "FAIL [suite] existing tests not all green (grc=$src)"
    tail -n 25 /tmp/bb_suite.log
fi
[ "$suite_ok" = 1 ] || say_fail "existing suite selection failed"

# ---------------------------------------------------------------------------
# 6. Diagnosis write-up sanity.
# ---------------------------------------------------------------------------
if ! grep -qi 'netrc' /app/diagnosis.md; then
    say_fail "/app/diagnosis.md does not mention the credentials-file feature"
fi

# ---------------------------------------------------------------------------
# Verdict.
# ---------------------------------------------------------------------------
if [ "$FAILS" -eq 0 ]; then
    echo "REWARD 1: crash fixed, golden+suite green, tree provenance clean"
    echo 1 > /logs/verifier/reward.txt
else
    echo "REWARD 0: $FAILS verifier failure(s)"
    echo 0 > /logs/verifier/reward.txt
fi
exit 0