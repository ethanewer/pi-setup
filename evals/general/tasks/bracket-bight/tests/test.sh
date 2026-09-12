#!/bin/bash
# bracket-bight verifier.
#
# Grades the agent's fix of the expressjs/express streaming bug at /app/src:
#   (1) provenance: relative to the pinned parent commit, only lib/response.js
#       may differ (untracked files included)
#   (2) the project's own regression test for the bug, test/res.send.js at the
#       upstream FIX commit (extracted to /opt/golden at image build time),
#       must pass against the agent's tree
#   (3) the project's own unit suite (test/) must still pass with its own
#       mocha runner
#   (4) authored hidden cases exercising the same code path with inputs the
#       upstream regression test does not use must pass
#   (5) the user-facing reproducer /app/reproduce.js must exit 0 with the
#       fixed header behaviour
#
# Writes 0/1 to /logs/verifier/reward.txt on every path (the EXIT trap covers
# any path that raises before writing).
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

PARENT=59e205a57a04fced6bb7b8ec0b5dec29461a9996
FIX=18e5985b8a9d5e8423db0a9121f22bdaecd5b120
MOCHA=/app/src/node_modules/.bin/mocha
FAILS=0

cd /app/src || { echo "FAIL: /app/src missing"; echo 0 > /logs/verifier/reward.txt; exit 0; }

if [ ! -x "$MOCHA" ]; then
    echo "FAIL: mocha not installed under /app/src/node_modules"
    echo 0 > /logs/verifier/reward.txt
    exit 0
fi

# ---------------------------------------------------------------------------
# (0) trusted-bytes integrity: the verifier executes code from the writable,
# gitignored node_modules tree (.bin/mocha) and loads supertest from it, and
# it runs /app/reproduce.js. Replacing those is the one way to pass every
# behavioral check without fixing the tracked source (demonstrated: fake
# mocha + stub supertest scored 1 with lib/response.js untouched). The image
# pinned their build-time bytes in /opt/golden/trusted.sha256; any drift is
# a hostile or accidental change, not a fix, and scores 0.
# ---------------------------------------------------------------------------
if [ -f /opt/golden/trusted.sha256 ]; then
    if ( cd /app/src \
         && { sha256sum /app/reproduce.js; \
              find node_modules \( -type f -o -type l \) -print0 | sort -z \
                | while IFS= read -r -d '' f; do \
                    if [ -L "$f" ]; then printf 'L %s -> %s\n' "$f" "$(readlink "$f")"; \
                    else sha256sum "$f"; fi; \
                  done; \
            } > /tmp/bb_trusted.now 2>/dev/null \
         && diff -q /opt/golden/trusted.sha256 /tmp/bb_trusted.now >/dev/null 2>&1 ); then
        echo "PASS [integrity] node_modules and /app/reproduce.js match the build-time manifest"
    else
        echo "FAIL [integrity] node_modules or /app/reproduce.js differ from the build-time manifest"
        echo "FAIL [integrity] faking the test runner or stubbing the HTTP client is not a fix"
        FAILS=$((FAILS + 1))
    fi
fi

# ---------------------------------------------------------------------------
# (1) provenance: the upstream tree must be unmodified except lib/response.js
# ---------------------------------------------------------------------------
provenance_ok=1
if [ "$(git rev-parse HEAD 2>/dev/null)" = "$PARENT" ]; then
    :
elif git cat-file -e "$PARENT^{commit}" 2>/dev/null; then
    # agent committed its work: tree diff vs the parent still decides
    :
else
    echo "FAIL [provenance] parent commit $PARENT not present in the clone"
    provenance_ok=0
fi
changed=$(git diff --name-only "$PARENT" 2>/dev/null)
for f in $changed; do
    if [ "$f" != "lib/response.js" ]; then
        echo "FAIL [provenance] upstream file differs from the parent: $f"
        provenance_ok=0
    fi
done
entries=$(git status --porcelain 2>/dev/null | sed 's/^...//' | sort -u)
for f in $entries; do
    if [ "$f" != "lib/response.js" ]; then
        echo "FAIL [provenance] unexpected working-tree entry: $f"
        provenance_ok=0
    fi
done
if [ "$provenance_ok" = 1 ]; then
    if git diff --quiet "$PARENT" -- lib/response.js 2>/dev/null; then
        echo "FAIL [provenance] lib/response.js is byte-identical to the parent; no fix change present"
        provenance_ok=0
    fi
fi
if [ "$provenance_ok" = 1 ]; then
    echo "PASS [provenance] upstream tree unmodified except lib/response.js"
else
    echo "FAIL [provenance] tree audit failed (see lines above)"
    FAILS=$((FAILS + 1))
fi

# ---------------------------------------------------------------------------
# (2) the upstream regression test from the fix commit, run in the project's
#     own tree with the project's own runner and support files
# ---------------------------------------------------------------------------
cp /opt/golden/res.send.js /app/src/test/res.send.js
if [ -f /opt/golden/res.send.js ] && timeout 300 "$MOCHA" --require test/support/env --reporter spec test/res.send.js > /tmp/bb_golden.out 2>&1; then
    echo "PASS [golden] upstream regression tests in test/res.send.js green"
else
    echo "FAIL [golden] test/res.send.js (upstream regression tests) not green"
    tail -n 40 /tmp/bb_golden.out 2>/dev/null
    FAILS=$((FAILS + 1))
fi

# ---------------------------------------------------------------------------
# (3) the project's own unit suite: mocha over test/ from /app/src
# ---------------------------------------------------------------------------
if timeout 420 "$MOCHA" --require test/support/env --reporter dot test/ > /tmp/bb_suite.out 2>&1; then
    echo "PASS [suite] project unit suite (test/) green"
else
    echo "FAIL [suite] project unit suite (test/) not green"
    tail -n 40 /tmp/bb_suite.out
    FAILS=$((FAILS + 1))
fi

# ---------------------------------------------------------------------------
# (4) authored hidden cases: same code path, inputs the upstream test does
#     not use (JSON bodies, Buffer bodies, long bodies, route-scoped TE)
# ---------------------------------------------------------------------------
hidden_ok=1
i=1
for dir in /tests/hidden/*/; do
    spec="$dir"spec.js
    [ -f "$spec" ] || continue
    cp "$spec" "/app/src/test/zzz_bb_hidden${i}.js"
    if timeout 120 "$MOCHA" --require test/support/env --reporter spec "/app/src/test/zzz_bb_hidden${i}.js" > "/tmp/bb_hidden${i}.out" 2>&1; then
        echo "PASS [hidden $i] $spec"
    else
        echo "FAIL [hidden $i] $spec"
        tail -n 30 "/tmp/bb_hidden${i}.out"
        hidden_ok=0
    fi
    i=$((i + 1))
done
[ "$hidden_ok" = 1 ] || { echo "FAIL [hidden] one or more hidden cases failed"; FAILS=$((FAILS + 1)); }

# ---------------------------------------------------------------------------
# (5) the user-facing reproducer: fixed behaviour, body delivered
# ---------------------------------------------------------------------------
if timeout 60 node /app/reproduce.js > /tmp/bb_repro.out 2>&1 \
        && grep -q "Content-Length present: false" /tmp/bb_repro.out \
        && grep -q "Transfer-Encoding present: true" /tmp/bb_repro.out \
        && grep -q 'body: "hello"' /tmp/bb_repro.out; then
    echo "PASS [repro] /app/reproduce.js exits 0 with fixed header behaviour"
    cat /tmp/bb_repro.out
else
    echo "FAIL [repro] /app/reproduce.js did not succeed with the fixed header behaviour"
    cat /tmp/bb_repro.out
    FAILS=$((FAILS + 1))
fi

# ---------------------------------------------------------------------------
# verdict (binary)
# ---------------------------------------------------------------------------
if [ "$FAILS" = 0 ]; then
    echo "REWARD 1: golden + project suite + hidden cases + reproducer all green"
    echo 1 > /logs/verifier/reward.txt
else
    echo "REWARD 0: $FAILS check(s) failed"
    echo 0 > /logs/verifier/reward.txt
fi
exit 0