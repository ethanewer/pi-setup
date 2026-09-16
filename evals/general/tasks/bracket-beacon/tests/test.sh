#!/bin/bash
# Verifier for bracket-beacon (upstream-clone regression task on DOMPurify).
#
# Requirements, in order:
#   0. the golden regression suite exists at /opt/golden/test-suite.js and
#      /app/src is a git checkout;
#   1. provenance: the checkout is still at the pinned parent commit, its
#      history is severed (shallow single-commit), the upstream fix commit
#      object is not present in the store, and the tracked working-tree diff
#      is non-empty and confined to the source fix plus regenerated dist/
#      output (no test, config or build-script changes — kills test-weakening
#      and build-disabling cheats);
#   2. the project's own build (`npm run build`) succeeds on the agent's
#      source and yields dist/purify.cjs.js;
#   3. the golden regression suite — the full fix-era project test-suite.js —
#      runs green through the project's own jsdom runner against the rebuilt
#      dist: exit 0, plan line 1..982, zero not-ok, and the two upstream
#      ADD_ATTR-function regression asserts present and passing;
#   4. every authored hidden case under /tests/hidden passes against the
#      rebuilt dist.
#
# Binary reward, written on every exit path (trap covers crashes).
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

SRC=/app/src
GOLDEN=/opt/golden/test-suite.js
PARENT_SHA=591c429c8db48797bdbd90a44f90d7ea5a88fbf7
FIX_SHA=6bc35973f0c6e7fa2344037af024fe0cf9cfa6e2
TAP=/tmp/bracket-beacon-suite.tap
failures=""

# Integrity anchors, captured at authoring time from the built task image:
#   GOLDEN_SHA256   sha256 of /opt/golden/test-suite.js extracted from the
#                   upstream FIX commit at image build time. The file lives in
#                   the image and the trial runs as root, so an agent could
#                   otherwise silently rewrite the "golden" regression suite
#                   into a trivially-passing one. The hash below is host-side
#                   (this script is uploaded fresh at verify time) and the fix
#                   commit is immutable, so this value never drifts.
#   NM_SHA256       sha256 over the content of the whole /app/src/node_modules
#                   tree in the built image. The build and test machinery under
#                   node_modules is untracked (invisible to the git-diff guard),
#                   and a malicious agent can wrap `npm run build` or stub qunit
#                   there to make an unfixed source tree produce a fixed dist.
#                   Hashing the tree closes that window. This constant is tied
#                   to the image content: changing the Dockerfile (or the npm
#                   resolution) requires recomputing it.
GOLDEN_SHA256=6306dfff1479d8f1f8d16ce3b4d25403c8efbe2dd5b6dbb9c4ace493e2f0e69f
NM_SHA256=2aad33e7f6e8175aef012e964c705d69bc8d8cd618c143a5397d93cd9c32e578

note_fail() {
    failures="$failures
- $1"
}

# ---- 0) environment sanity ----------------------------------------------
if [ ! -f "$GOLDEN" ]; then
    note_fail "golden regression suite missing at $GOLDEN"
fi
if [ ! -d "$SRC/.git" ]; then
    note_fail "/app/src is not a git checkout"
fi

# ---- 1) provenance -------------------------------------------------------
if [ -f "$GOLDEN" ]; then
    actual=$(sha256sum "$GOLDEN" | awk '{print $1}')
    if [ "$actual" != "$GOLDEN_SHA256" ]; then
        note_fail "golden regression suite does not match the fix-commit bytes (sha256 $actual != $GOLDEN_SHA256); it was tampered with or the image was rebuilt"
    fi
else
    note_fail "golden regression suite missing at $GOLDEN"
fi
if [ -d "$SRC/node_modules" ]; then
    nmtree=$(cd "$SRC" && find node_modules -type f -not -path "*/.*" -print0 | sort -z | xargs -0 sha256sum | sha256sum | awk '{print $1}')
    if [ "$nmtree" != "$NM_SHA256" ]; then
        note_fail "node_modules tree has been modified (tree sha256 $nmtree != $NM_SHA256); build/test machinery must not be tampered with"
    fi
else
    note_fail "node_modules missing under $SRC; the build cannot run"
fi
if [ -d "$SRC/.git" ]; then
    head_sha=$(git -C "$SRC" rev-parse HEAD 2>/dev/null || true)
    if [ "$head_sha" != "$PARENT_SHA" ]; then
        note_fail "checkout HEAD is ${head_sha:-<none>}, expected the pinned revision $PARENT_SHA"
    fi
    count=$(git -C "$SRC" rev-list --count HEAD 2>/dev/null || true)
    if [ "$count" != "1" ]; then
        note_fail "checkout history is not severed (rev-list --count HEAD = ${count:-<none>}; expected 1 shallow commit)"
    fi
    if git -C "$SRC" cat-file -e "$FIX_SHA^{commit}" 2>/dev/null; then
        note_fail "an object for the upstream fix commit is reachable from the checkout store"
    fi
    guard=$(git -C "$SRC" diff --name-only --diff-filter=ACDMRT HEAD 2>/dev/null || true)
    if [ -z "$guard" ]; then
        note_fail "no tracked change at all (git diff empty); the regression is still present"
    else
        bad=$(printf '%s\n' "$guard" | python3 -c '
import re, sys
ok = 0
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    if line == "src/purify.ts" or line.startswith("dist/"):
        ok += 1
    else:
        print(line)
' | head -10)
        if [ -n "$bad" ]; then
            note_fail "tracked diff touches files outside the source fix and the dist/ rebuild:"
            note_fail "$bad"
        fi
    fi
fi

# ---- 2) rebuild dist/ from the agent's source (project's own build) ------
buildlog=/tmp/bracket-beacon-build.log
if ( cd "$SRC" && npm run build > "$buildlog" 2>&1 ); then
    if [ -f "$SRC/dist/purify.cjs.js" ]; then
        echo "build: npm run build ok"
    else
        note_fail "npm run build succeeded but dist/purify.cjs.js is missing"
    fi
else
    note_fail "npm run build failed:"
    tail -15 "$buildlog" | sed 's/^/    /'
fi

# ---- 3) golden regression suite via the project's own runner -------------
if [ -f "$GOLDEN" ] && [ -f "$SRC/dist/purify.cjs.js" ]; then
    backup=$(mktemp)
    cp "$SRC/test/test-suite.js" "$backup"
    cp "$GOLDEN" "$SRC/test/test-suite.js"
    ( cd "$SRC" && node test/jsdom-node-runner > "$TAP" 2>&1 )
    src=$?
    cp "$backup" "$SRC/test/test-suite.js"
    rm -f "$backup"
    echo "suite: runner exit $src"
    if [ "$src" -ne 0 ]; then
        note_fail "golden regression suite exited $src (a fix must make every case pass)"
    fi
    if grep -qE '^[ ]?not ok' "$TAP"; then
        note_fail "golden regression suite has failing cases:"
        grep -E '^[ ]?not ok' "$TAP" | head -5 | sed 's/^/    /'
    fi
    if ! grep -q '^1\.\.982$' "$TAP"; then
        note_fail "suite plan line '1..982' not found (suite did not run to completion?)"
    fi
    if ! grep -Eq '^ok [0-9]+ - ADD_ATTR function: javascript: URI must be stripped from href' "$TAP"; then
        note_fail "golden assert 'ADD_ATTR function: javascript: URI must be stripped from href' did not pass"
    fi
    if ! grep -Eq '^ok [0-9]+ - ADD_ATTR function: safe URI must be preserved in href' "$TAP"; then
        note_fail "golden assert 'ADD_ATTR function: safe URI must be preserved in href' did not pass"
    fi
    okcount=$(grep -c '^ok ' "$TAP" || true)
    echo "suite: $okcount ok"
fi

# ---- 4) authored hidden cases through the rebuilt dist -------------------
if [ -f "$SRC/dist/purify.cjs.js" ]; then
    hlog=/tmp/bracket-beacon-hidden.log
    if ( cd "$SRC" && NODE_PATH=/app/src/node_modules node /tests/verify_hidden.js > "$hlog" 2>&1 ); then
        echo "hidden: all cases passed"
    else
        note_fail "hidden cases failed:"
        sed 's/^/    /' "$hlog" | head -20
    fi
fi

# ---- 5) reward ------------------------------------------------------------
if [ -z "$failures" ]; then
    echo "ALL CHECKS PASSED"
    echo 1 > /logs/verifier/reward.txt
else
    echo "VERIFICATION FAILED:"
    printf '%s\n' "$failures"
    echo 0 > /logs/verifier/reward.txt
fi
exit 0