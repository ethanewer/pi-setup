#!/bin/bash
# Verifier for cistern-cleat: an upstream-clone debugging task on gin.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# Context.ClientIP() only consulted the first line of a repeated forwarded
# client-IP header, so multi-line X-Forwarded-For chains appended by proxies
# reported the leftmost address instead of the rightmost untrusted one.  The
# verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit object is absent from the working clone, only the
#      minimal tracked source file is modified, nothing was added);
#   1. runs the project's own regression tests for this bug, extracted at
#      image build time from the fix commit into /opt/golden/, against a
#      throwaway copy of the tree (the deliverable is never modified);
#   2. runs gin's own existing test suite (packages gin, gin/binding and
#      gin/render, exactly as the project's Makefile does) from a pristine
#      copy, proving the fix broke nothing else;
#   3. runs authored hidden cases from /tests/hidden/ (a three-line proxy
#      chain, an alternative trusted header X-Real-IP, and malformed lines)
#      from inputs the upstream tests do not use.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=915e4c90d28ec4cffc6eb146e208ab5a65eac772
FIX_SHA=9914178584e42458ff7d23891463a880f58c9d86
GOLDEN=/opt/golden/context_test.go
GO_BIN=/opt/go/bin/go
export GO111MODULE=on GOMODCACHE=/opt/gomodcache GOCACHE=/opt/gocache

# ---------- fixture + toolchain integrity -----------------------------------
# The trial runs as root in the environment container, so an agent could try
# to substitute the go toolchain by a wrapper that always exits 0, or to
# rewrite the golden regression tests. /opt/golden and the toolchain live in
# the image and are NOT re-uploaded at verify time, so the verifier itself
# must check them. This file lives on the host (/tests is re-uploaded before
# the verifier runs) which is out of the agent's reach. The hashes below are
# pinned to: the official go1.24.0 linux-amd64 binary in this image, the
# upstream context_test.go blob at fix commit 9914178584, and the authored
# hidden cases in this task.
GO_BIN_SHA256=97788e7e91584bda693b8dc669c58ba3346cfd50de241aecba27ddd68d8098ff
GO_VERSION_STR="go version go1.24.0 linux/amd64"
GOLDEN_SHA256=e05800be8c68893e8ca37d924763306a478d641fab2e6810c76b01cbd23e2d5f
# Tree manifests of the pristine image: the whole go1.24.0 toolchain tree
# (/opt/go, includes the stdlib) and the warmed module cache
# (/opt/gomodcache, includes testify). The agent could otherwise rewrite a
# module's extracted sources (e.g. neutralize assert.Equal) or the stdlib
# (reflect.DeepEqual) and get a vacuous PASS; go does not re-verify the
# extracted module tree on every build. Verified stable across go test runs.
GO_TREE_SHA256=378f5ec7a9347a40b6df19d6769234009bd37720d70f9829d0a5edfcf1d28a45
MODCACHE_SHA256=121128e28710af9161c341a6de21b8f8c6e155ae7a02f4a495f1ba4801d56b7d

integrity_fail () {
  echo "FAIL: $1" >&2
  reward=0
}

treehash () {
  find "$1" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1
}

if [ ! -f "$GO_BIN" ] || [ "$(sha256sum "$GO_BIN" 2>/dev/null | cut -d' ' -f1)" != "$GO_BIN_SHA256" ]; then
  integrity_fail "go toolchain integrity check failed ($GO_BIN was tampered with; score 0 without trusting it)"
  echo "REWARD=$reward"; echo "$reward" > /logs/verifier/reward.txt; exit 0
fi
if [ "$(/usr/local/bin/go version 2>/dev/null)" != "$GO_VERSION_STR" ]; then
  integrity_fail "unexpected go version string (tampered toolchain); score 0"
  echo "REWARD=$reward"; echo "$reward" > /logs/verifier/reward.txt; exit 0
fi
if [ "$(treehash /opt/go 2>/dev/null)" != "$GO_TREE_SHA256" ]; then
  integrity_fail "/opt/go tree does not match the pristine toolchain (stdlib or tool files tampered); score 0 without trusting it"
  echo "REWARD=$reward"; echo "$reward" > /logs/verifier/reward.txt; exit 0
fi
if [ "$(treehash /opt/gomodcache 2>/dev/null)" != "$MODCACHE_SHA256" ]; then
  integrity_fail "/opt/gomodcache tree does not match the pristine module cache (test dependency tampered); score 0 without trusting it"
  echo "REWARD=$reward"; echo "$reward" > /logs/verifier/reward.txt; exit 0
fi
echo "ok: go toolchain integrity ($GO_VERSION_STR)"
echo "ok: toolchain tree and module cache match the pristine image"

# run_go_test LABEL OUT DIR args...
# Runs `go test` with the given args from DIR (a throwaway copy of the tree).
run_go_test () {
  label="$1"; out="$2"; dir="$3"; shift 3
  if ( cd "$dir" && go test "$@" > "$out" 2>&1 ); then
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
  echo "ok: fix commit object is absent from the working clone"
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
bad=$(printf '%s\n' "$porcelain" | grep -vE '^( M|M |MM) context\.go$' || true)
if [ -n "$bad" ]; then
  echo "FAIL: unexpected working-tree changes (only context.go may be modified, and nothing added):" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
else
  echo "ok: no tracked files other than context.go are modified and nothing was added"
fi
if ! printf '%s\n' "$porcelain" | grep -q 'context\.go'; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2
  reward=0
fi
if [ -z "$(git -C "$SRC" diff -- context.go 2>/dev/null || true)" ]; then
  echo "FAIL: context.go has no diff (no fix was implemented)" >&2
  reward=0
fi

# ---------- 1. golden: the upstream regression tests --------------------------
echo "== golden tests (upstream regression tests for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test file missing from image" >&2; reward=0
elif [ "$(sha256sum "$GOLDEN" 2>/dev/null | cut -d' ' -f1)" != "$GOLDEN_SHA256" ]; then
  echo "FAIL: golden test file does not match the upstream fix-commit bytes (tampered)" >&2; reward=0
else
  rm -rf /tmp/v-golden
  cp -a "$SRC" /tmp/v-golden
  cp "$GOLDEN" /tmp/v-golden/context_test.go
  run_go_test "golden TestContextClientIPWith(MultipleHeaders|SingleHeader)" \
      /tmp/golden.out /tmp/v-golden \
      -v github.com/gin-gonic/gin -test.run "TestContextClientIPWith(MultipleHeaders|SingleHeader)" \
    || true
fi

# ---------- 2. the project's own existing suite -------------------------------
echo "== gin's own existing test suite (Makefile package list) =="
rm -rf /tmp/v-suite
cp -a "$SRC" /tmp/v-suite
run_go_test "own suite github.com/gin-gonic/gin" /tmp/suite-gin.out /tmp/v-suite \
    -v github.com/gin-gonic/gin || true
run_go_test "own suite github.com/gin-gonic/gin/binding" /tmp/suite-binding.out /tmp/v-suite \
    -v github.com/gin-gonic/gin/binding || true
run_go_test "own suite github.com/gin-gonic/gin/render" /tmp/suite-render.out /tmp/v-suite \
    -v github.com/gin-gonic/gin/render || true

# ---------- 3. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
n_dirs=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_dirs=$((n_dirs + 1))
  basename_case=$(basename "$case")
  case "$basename_case" in
    case-chain|case-realip|case-robust) : ;;
    *) echo "FAIL: unexpected hidden case directory $basename_case (tampered /tests)" >&2; reward=0; continue ;;
  esac
  for testfile in "$case"zz_hidden_*_test.go; do
    [ -f "$testfile" ] || continue
    h=$(sha256sum "$testfile" 2>/dev/null | cut -d' ' -f1)
    expected=""
    case "$basename_case" in
      case-chain)  expected=f9066fa88fa5687b37f4580d84a7a072529b02e19c42f1debda29175f5dfa9f8 ;;
      case-realip) expected=4b876c90a97714c107f38641b304cc814bb47cfa62d15e5a22edfa4901e1cdaf ;;
      case-robust) expected=af4d5f1065ba12db776d28be4f3bf543b7fe88b1408f18ef8b049a952df67b54 ;;
    esac
    if [ -n "$expected" ] && [ "$h" != "$expected" ]; then
      echo "FAIL: hidden case file $testfile does not match the shipped bytes (tampered)" >&2; reward=0
    fi
  done
  rm -rf "/tmp/v-hidden-$basename_case"
  cp -a "$SRC" "/tmp/v-hidden-$basename_case"
  cp "$case"zz_hidden_*_test.go "/tmp/v-hidden-$basename_case/"
  out="/tmp/hidden-${basename_case}.out"
  if run_go_test "hidden case $basename_case" "$out" "/tmp/v-hidden-$basename_case" \
      -v github.com/gin-gonic/gin -test.run TestHidden; then
    n_hidden=$((n_hidden + 1))
  fi
done
if [ "$n_dirs" -ne 3 ]; then
  echo "FAIL: expected exactly 3 hidden case directories, found $n_dirs (tampered /tests)" >&2; reward=0
fi
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases passed" >&2; reward=0
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0