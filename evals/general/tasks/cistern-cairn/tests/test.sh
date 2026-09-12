#!/bin/bash
# Verifier for cistern-cairn: an upstream-clone debugging task on express.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# res.clearCookie lets a caller's maxAge or explicit expires date override the
# forced past expiry, so a cleared cookie can survive (or be re-created) with
# a future Expires / a Max-Age instead of being removed. The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, only the
#      minimal tracked source file is modified, and that file is changed);
#   1. runs the project's own regression test for this bug, extracted at image
#      build time from the fix commit into /opt/golden/ (4 upstream tests);
#   2. runs the project's own existing cookie test files from the tree,
#      proving the fix broke nothing else;
#   3. runs at least three authored hidden cases (large keep-alive maxAge with
#      domain/httpOnly, far-future expires plus a negative maxAge, and
#      secure/sameSite) that the upstream tests do not cover.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=160b91cbf79b595712b694c3513c347551d17fbe
FIX_SHA=82fc12a40b3e6694e9a2c9b1376e7548d95779f6
GOLDEN=/opt/golden/res.clearCookie.js
export NODE_PATH="$SRC/node_modules"

run_mocha () {  # run_mocha LABEL OUT ...args  (mocha args are paths to test files)
  label="$1"; out="$2"; shift 2
  # --no-config --no-package: never load .mocharc.* / package.json config from
  # the agent's tree. Otherwise an untracked .mocharc.js (invisible to git
  # status) can inject a require() hook that monkey-patches res.clearCookie at
  # test-run time and make every test pass while the tracked source keeps the
  # bug -- a bypass confirmed during review.
  if ( cd "$SRC" && ./node_modules/.bin/mocha --no-config --no-package --require test/support/env "$@" > "$out" 2>&1 ); then
    echo "ok: $label"
    return 0
  fi
  echo "FAIL: $label" >&2
  tail -40 "$out" | sed 's/^/    /' >&2
  reward=0
  return 1
}

# ---------- 0. tree provenance -----------------------------------------------
echo "== tree provenance =="
if [ ! -d "$SRC/.git" ]; then
  echo "FAIL: /app/src is not a git clone" >&2; reward=0
elif [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  echo "FAIL: /app/src HEAD is not the pinned parent commit" >&2; reward=0
else
  echo "ok: HEAD is $PARENT_SHA"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  echo "FAIL: the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)" >&2
  reward=0
else
  echo "ok: fix commit NOT reachable from the working clone"
fi

# node_modules and package-lock are gitignored upstream, so an untouched tree
# is clean here. Only the single buggy tracked source file may be modified;
# untracked files the agent may have added are tolerated (they cannot affect
# the packaged code, which is loaded from the tracked lib/).
porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
bad=$(printf '%s\n' "$porcelain" | grep -v '^ M lib/response.js$' | grep -v '^?? ' || true)
if [ -n "$bad" ]; then
  echo "FAIL: unexpected working-tree changes (only lib/response.js may be modified):" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
fi
if [ -z "$(git -C "$SRC" diff -- lib/response.js 2>/dev/null || true)" ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2
  reward=0
else
  echo "ok: lib/response.js is modified"
fi

# ---------- 0b. the fix must live IN the tracked source -----------------------
# Behavioural tests alone cannot tell where a fix landed: review confirmed
# that a monkey-patch injected via untracked .mocharc.js, or a patch to the
# gitignored node_modules/cookie serializer, makes every hidden and golden
# test pass with lib/response.js still buggy. So assert the tracked source
# itself implements the fix: clearCookie must force a past expiry and strip
# maxAge before the options reach res.cookie.
body="$(awk '/res\.clearCookie = function clearCookie\(name, options\)/{scan=1} scan{print} scan && /^};/{exit}' "$SRC/lib/response.js")"
if [ -z "$body" ]; then
  echo "FAIL: res.clearCookie function body not found in lib/response.js" >&2
  reward=0
elif ! printf '%s\n' "$body" | grep -Eq 'new Date\([01]\)'; then
  echo "FAIL: lib/response.js clearCookie does not force a past expiry (no 'new Date(0)' / 'new Date(1)') in the tracked source" >&2
  reward=0
elif ! printf '%s\n' "$body" | grep -Eq 'delete[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*\.maxAge|maxAge[[:space:]]*=[[:space:]]*(undefined|null)'; then
  echo "FAIL: lib/response.js clearCookie does not strip maxAge before calling this.cookie" >&2
  reward=0
else
  echo "ok: tracked lib/response.js clearCookie forces a past expiry and strips maxAge"
fi

# node_modules is gitignored, so a patch to it is invisible to git status.
# The behavioural tests load the serializer from node_modules/cookie (exact
# pin 0.6.0, deterministic across rebuilds); assert it is pristine against
# the fixed constant below.
COOKIE_SHA=9fd02358eabdf6c27b388dfdff94061655620a352253bfc5b01ee4cc30ca36b5
if [ "$(sha256sum "$SRC/node_modules/cookie/index.js" | awk '{print $1}')" != "$COOKIE_SHA" ]; then
  echo "FAIL: node_modules/cookie/index.js differs from the pristine install (dependency patched to fake the fix)" >&2
  reward=0
else
  echo "ok: node_modules/cookie serializer is pristine"
fi

# ---------- 1. golden: the upstream regression test ---------------------------
echo "== golden test (upstream regression test for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
elif [ "$(sha256sum "$GOLDEN" | awk '{print $1}')" != "83d883aebfb0e17d1d9fb864c1a52599d1070b2d45af7f9b591acad3ca614882" ]; then
  # The golden file is extracted once at image build time from the upstream
  # FIX commit; this sha pins that exact content. The agent runs as root and
  # could rewrite /opt/golden to neutralise the upstream regression tests, so
  # integrity is asserted against this constant before anything is copied.
  echo "FAIL: /opt/golden/res.clearCookie.js has been modified (does not match the sha of the file extracted from the upstream fix commit)" >&2
  reward=0
else
  # The upstream test resolves express via require('../'), so it must be run
  # from inside the tree; run it from a throwaway directory removed below.
  GM="$SRC/.verifier-golden"
  rm -rf "$GM"; mkdir -p "$GM"
  cp "$GOLDEN" "$GM/res.clearCookie.js"
  run_mocha "golden res.clearCookie (4 upstream tests)" /tmp/golden.out "$GM/res.clearCookie.js" \
    || true
  rm -rf "$GM"
fi

# ---------- 2. the project's own existing cookie tests ------------------------
echo "== the project's own existing cookie tests =="
run_mocha "existing test/res.clearCookie.js" /tmp/own-clear.out test/res.clearCookie.js \
  || true
run_mocha "existing test/res.cookie.js" /tmp/own-cookie.out test/res.cookie.js \
  || true

# ---------- 3. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  file=$(find "$case" -maxdepth 1 -name '*.js' | head -1)
  if [ -n "$file" ] && run_mocha "hidden case $name" "$out" "$file"; then
    echo "ok: hidden case $name"
  else
    echo "FAIL: hidden case $name" >&2
    [ -n "$file" ] && tail -40 "$out" | sed 's/^/    /' >&2
    reward=0
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases were exercised" >&2; reward=0
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0
