#!/bin/bash
# Verifier for gasket-wake: an upstream-clone debugging task on gin-gonic/gin.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# with RedirectFixedPath enabled, the case-insensitive fixed-path lookup
# panics with "invalid node type" and kills the server whenever the routing
# tree has a node with both static children and a wildcard (param or
# catch-all) child. The agent must ALSO author its own failing reproduction
# at /app/repro_caseinsensitive_test.go and leave it as a deliverable.
#
# The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit object is absent, remotes untouched, only tree.go
#      modified, nothing added), and fixture/toolchain integrity (go binary
#      hash and version, toolchain tree, module/build caches, golden files);
#   1. runs the AGENT'S OWN reproduction twice: on a copy of the tree with
#      the pristine buggy tree.go restored it must FAIL (that is what proves
#      the reproduction actually reproduces the bug), and on the repaired
#      tree it must PASS;
#   2. runs the project's own upstream regression tests for this bug,
#      extracted at image build time from the fix commit into /opt/golden/,
#      overlaid on a throwaway copy of the repaired tree;
#   3. runs the project's own existing suites (packages gin, gin/binding and
#      gin/render, exactly as the project's Makefile does) from pristine
#      copies, proving the fix broke nothing else;
#   4. runs at least two authored hidden cases from /tests/hidden/ (a deeper
#      mixed static/param subtree, a router-level request through
#      RedirectFixedPath, and a static leaf + catch-all sibling) from inputs
#      the upstream tests do not use, across throwaway copies.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=fb2583442c4d9bccb75e6d26f1aa6e7c01950db6
FIX_SHA=472d086af2acd924cb4b9d7be0525f7d790f69bc
GOLDEN=/opt/golden/tree_test.go
PRISTINE=/opt/golden/tree.go.parent
MANIFEST=/opt/golden/manifest.txt
REPRO=/app/repro_caseinsensitive_test.go
GO_BIN=/usr/local/go/bin/go

# Fixtures and toolchain are part of the image; an agent that tampers with
# them (go binary wrapper, rewritten golden tests, edited module sources,
# swapped pristine source) must score 0 before any fixture is trusted. The
# hashes below are pinned to the pristine image bytes; /tests is re-uploaded
# from the host before the verifier runs, so the hidden cases are checked
# against the shipped bytes too.
GOLDEN_SHA256=29fddc7f518a711e8287107bc95a554970797d3b9a7745e78fd50a85810e0d66
PRISTINE_SHA256=1c8146f32b2e0544037fe3996f0c92f1a422547983a653f85a93910a5c4e710e
MANIFEST_SHA256=0e9394e5864af91b58b8d767b38416f9a0dd3137b0f04784ad2638ef5f6d908f
GO_BIN_SHA256=d9a2fa19c7ef8b57f420012c21f49f235c46f08a68c12077d9c753dbb6ccdc34
GO_VERSION_STR="go version go1.26.8 linux/amd64"
GO_TREE_SHA256=5567162f1a1a1ec4b6be81285e76c4f0d484d20236498b4d31294ce29f143211
GOPKG_SHA256=008f2758a4330c796952e5a75e5d35ccc4bb3b30d9510d1632402b71fb44e21a
HIDDEN_SHA256_case_deep=2092cbe49513f34c500d3f91df4d4e56f5db9d7ba3147a55597fcca5981d9a80
HIDDEN_SHA256_case_router=cd79f51a82a6483544a756e4fee9da8d905128e386913e79b5b7774dc17a254e
HIDDEN_SHA256_case_catchall=3f9b3fba9af0dced36a6e8334a37af3c5e5ece4d37308f8e04e008cbbabc4488

export PATH=/usr/local/go/bin:$PATH GO111MODULE=on

fail () {  # fail MESSAGE
  echo "FAIL: $1" >&2
  reward=0
}

treehash () {  # treehash DIR  -- content hash over the file tree
  find "$1" -type f -print0 2>/dev/null | sort -z | xargs -0 sha256sum 2>/dev/null | sha256sum | cut -d' ' -f1
}

# run_expect_pass LABEL DIR OUT ARGS...
run_expect_pass () {
  label="$1"; dir="$2"; out="$3"; shift 3
  if ( cd "$dir" && go test "$@" > "$out" 2>&1 ); then
    echo "ok: $label"
    return 0
  fi
  echo "FAIL: $label" >&2
  tail -40 "$out" | sed 's/^/    /' >&2
  reward=0
  return 1
}

# ---------- 0a. toolchain + fixture integrity --------------------------------
echo "== toolchain and fixture integrity =="
if [ ! -f "$GO_BIN" ] || [ "$(sha256sum "$GO_BIN" 2>/dev/null | cut -d' ' -f1)" != "$GO_BIN_SHA256" ]; then
  fail "go toolchain integrity check failed ($GO_BIN tampered; score 0 without trusting it)"
  echo "REWARD=$reward"; echo "$reward" > /logs/verifier/reward.txt; exit 0
fi
if [ "$("$GO_BIN" version 2>/dev/null)" != "$GO_VERSION_STR" ]; then
  fail "unexpected go version string; score 0"
  echo "REWARD=$reward"; echo "$reward" > /logs/verifier/reward.txt; exit 0
fi
if [ "$(treehash /usr/local/go)" != "$GO_TREE_SHA256" ]; then
  fail "/usr/local/go tree does not match the pristine toolchain; score 0 without trusting it"
  echo "REWARD=$reward"; echo "$reward" > /logs/verifier/reward.txt; exit 0
fi
if [ -d /root/go ] && [ "$(treehash /root/go)" != "$GOPKG_SHA256" ]; then
  fail "/root/go module cache changed from the pristine image; score 0"
  echo "REWARD=$reward"; echo "$reward" > /logs/verifier/reward.txt; exit 0
fi
if [ "$(sha256sum "$GOLDEN" 2>/dev/null | cut -d' ' -f1)" != "$GOLDEN_SHA256" ]; then
  fail "golden tree_test.go does not match the upstream fix-commit bytes; score 0"
  echo "REWARD=$reward"; echo "$reward" > /logs/verifier/reward.txt; exit 0
fi
if [ "$(sha256sum "$PRISTINE" 2>/dev/null | cut -d' ' -f1)" != "$PRISTINE_SHA256" ]; then
  fail "pristine tree.go.parent restored-source copy does not match the image bytes; score 0"
  echo "REWARD=$reward"; echo "$reward" > /logs/verifier/reward.txt; exit 0
fi
if [ "$(sha256sum "$MANIFEST" 2>/dev/null | cut -d' ' -f1)" != "$MANIFEST_SHA256" ]; then
  fail "pristine tree manifest does not match the image bytes; score 0"
  echo "REWARD=$reward"; echo "$reward" > /logs/verifier/reward.txt; exit 0
fi
echo "ok: go $GO_VERSION_STR, toolchain tree and caches pristine, golden and pristine fixtures byte-identical"

# ---------- 0b. tree provenance -----------------------------------------------
echo "== tree provenance =="
if [ ! -d "$SRC/.git" ]; then
  fail "/app/src is not a git clone"
elif [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  fail "/app/src HEAD is not the pinned parent commit"
else
  echo "ok: HEAD is $PARENT_SHA"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  fail "the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)"
else
  echo "ok: the upstream fix commit object is absent from the working clone"
fi

remotes=$(git -C "$SRC" remote 2>/dev/null || true)
if [ "$remotes" != "origin" ]; then
  fail "unexpected git remotes: ${remotes:-<none>}"
else
  echo "ok: remotes untouched (origin only)"
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
bad=""
while IFS= read -r line; do
  case "$line" in
    "") ;;
    " M tree.go") ;;
    *) bad="${bad}${line}" ;;
  esac
done <<EOF
$porcelain
EOF
if [ -n "$bad" ]; then
  fail "unexpected working-tree state (only tree.go may be modified, nothing staged, no new files):"
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
fi
if [ -z "$(git -C "$SRC" diff -- tree.go 2>/dev/null || true)" ]; then
  fail "the deliverable /app/src is unchanged: tree.go has no modifications (no fix was implemented)"
else
  echo "ok: tree.go differs from the pinned commit (fix present)"
fi

# Content pin: every file under /app/src except tree.go must be byte-identical
# to the pristine tree (catches test-file tampering hidden from git status via
# update-index --assume-unchanged, extra scratch files, and edited module or
# fixture sources).
if [ -f "$MANIFEST" ] && [ "$(sha256sum "$MANIFEST" | cut -d' ' -f1)" = "$MANIFEST_SHA256" ]; then
  cur=$(cd "$SRC" && find . -path ./.git -prune -o -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sed 's#  \./#  #' | awk '$2 != "tree.go"')
  ref=$(awk '$2 != "tree.go"' "$MANIFEST")
  if [ "$cur" != "$ref" ]; then
    fail "files under /app/src changed beyond tree.go (extra, missing or modified files)"
    diff <(printf '%s\n' "$ref") <(printf '%s\n' "$cur") 2>/dev/null | head -10 | sed 's/^/    /' >&2 || true
  else
    echo "ok: every file under /app/src except tree.go matches the pristine manifest"
  fi
fi

# ---------- 1. the agent's own reproduction -----------------------------------
echo "== the agent's own reproduction =="
if [ ! -s "$REPRO" ]; then
  fail "reproduction deliverable $REPRO is missing or empty"
fi
if [ -s "$REPRO" ] && ! grep -qE 'func TestRepro' "$REPRO"; then
  fail "reproduction deliverable has no test function named TestRepro*"
fi

if [ -s "$REPRO" ] && [ "$reward" = 1 ]; then
  # 1a. the reproduction must genuinely reproduce: it must FAIL on a copy of
  # the tree with the pristine buggy source restored.
  rm -rf /tmp/v-repro-pre
  cp -a "$SRC" /tmp/v-repro-pre
  cp "$PRISTINE" /tmp/v-repro-pre/tree.go
  cp "$REPRO" /tmp/v-repro-pre/
  if ( cd /tmp/v-repro-pre && go test -v github.com/gin-gonic/gin -test.run 'TestRepro' > /tmp/repro-pre.out 2>&1 ); then
    fail "the reproduction PASSED on the pristine pre-fix tree; it does not reproduce the bug"
    tail -20 /tmp/repro-pre.out | sed 's/^/    /' >&2
  elif ! grep -qE 'TestRepro' /tmp/repro-pre.out; then
    fail "the reproduction did not run on the pre-fix tree (no TestRepro* test executed; compile error or empty filter)"
    tail -20 /tmp/repro-pre.out | sed 's/^/    /' >&2
  else
    if grep -qE 'panic: invalid node type|recovered, repanicked|--- FAIL' /tmp/repro-pre.out; then
      echo "ok: reproduction fails on the pre-fix tree as expected"
      grep -m2 -E 'panic: invalid node type|--- FAIL' /tmp/repro-pre.out | sed 's/^/    /'
    else
      echo "note: reproduction failed on the pre-fix tree (see below), which is still an acceptable reproduction"
      grep -m3 -E 'TestRepro|PANIC|FAIL|Error' /tmp/repro-pre.out | sed 's/^/    /' || true
    fi
  fi

  # 1b. the reproduction must PASS on the repaired tree.
  rm -rf /tmp/v-repro-fixed
  cp -a "$SRC" /tmp/v-repro-fixed
  cp "$REPRO" /tmp/v-repro-fixed/
  if ( cd /tmp/v-repro-fixed && go test -v github.com/gin-gonic/gin -test.run 'TestRepro' > /tmp/repro-fixed.out 2>&1 ); then
    nmatch=$(grep -cE -- '--- PASS: TestRepro' /tmp/repro-fixed.out || true)
    if [ "$nmatch" -ge 1 ]; then
      echo "ok: reproduction passes on the repaired tree ($nmatch TestRepro* tests)"
    else
      fail "reproduction run passed but no TestRepro* test actually executed"
      tail -10 /tmp/repro-fixed.out | sed 's/^/    /' >&2
    fi
  else
    fail "the reproduction FAILED on the repaired tree"
    tail -30 /tmp/repro-fixed.out | sed 's/^/    /' >&2
  fi
fi

# ---------- 2. golden: the upstream regression tests --------------------------
echo "== golden tests (upstream regression tests for this bug) =="
if [ "$reward" = 1 ]; then
  rm -rf /tmp/v-golden
  cp -a "$SRC" /tmp/v-golden
  cp "$GOLDEN" /tmp/v-golden/tree_test.go
  run_expect_pass "golden TestTreeFindCaseInsensitivePath(WithMultipleChildrenAndWildcard|WildcardParamAndStaticChild)" \
      /tmp/v-golden /tmp/golden.out \
      -v github.com/gin-gonic/gin \
      -test.run 'TestTreeFindCaseInsensitivePath(WithMultipleChildrenAndWildcard|WildcardParamAndStaticChild)' \
    || true
  for name in TestTreeFindCaseInsensitivePathWithMultipleChildrenAndWildcard \
              TestTreeFindCaseInsensitivePathWildcardParamAndStaticChild; do
    if grep -qE "^--- PASS: $name" /tmp/golden.out 2>/dev/null; then
      echo "ok: golden test passes: $name"
    else
      fail "golden test did not pass: $name"
    fi
  done
fi

# ---------- 3. the project's own existing suite -------------------------------
echo "== the project's own existing suite =="
if [ "$reward" = 1 ]; then
  rm -rf /tmp/v-suite
  cp -a "$SRC" /tmp/v-suite
  run_expect_pass "own suite github.com/gin-gonic/gin" /tmp/v-suite /tmp/suite-gin.out \
      -v github.com/gin-gonic/gin || true
  run_expect_pass "own suite github.com/gin-gonic/gin/binding" /tmp/v-suite /tmp/suite-binding.out \
      -v github.com/gin-gonic/gin/binding || true
  run_expect_pass "own suite github.com/gin-gonic/gin/render" /tmp/v-suite /tmp/suite-render.out \
      -v github.com/gin-gonic/gin/render || true
fi

# ---------- 4. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
n_dirs=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_dirs=$((n_dirs + 1))
  cname=$(basename "$case")
  case "$cname" in
    case-deep|case-router|case-catchall) : ;;
    *) fail "unexpected hidden case directory $cname (tampered /tests)"; continue ;;
  esac
  testfile=""
  for f in "$case"zz_hidden_*_test.go; do
    [ -f "$f" ] && testfile="$f"
  done
  if [ -z "$testfile" ]; then
    fail "hidden case $cname has no zz_hidden_*_test.go"
    continue
  fi
  h=$(sha256sum "$testfile" 2>/dev/null | cut -d' ' -f1)
  expected=""
  case "$cname" in
    case-deep)     expected=$HIDDEN_SHA256_case_deep ;;
    case-router)   expected=$HIDDEN_SHA256_case_router ;;
    case-catchall) expected=$HIDDEN_SHA256_case_catchall ;;
  esac
  if [ "$h" != "$expected" ]; then
    fail "hidden case file $testfile does not match the shipped bytes (tampered /tests)"
    continue
  fi
  filter=""
  case "$cname" in
    case-deep)     filter=TestHiddenCaseDeep ;;
    case-router)   filter=TestHiddenCaseRouter ;;
    case-catchall) filter=TestHiddenCaseCatchAll ;;
  esac
  rm -rf "/tmp/v-hidden-$cname"
  cp -a "$SRC" "/tmp/v-hidden-$cname"
  cp "$testfile" "/tmp/v-hidden-$cname/"
  if run_expect_pass "hidden case $cname" "/tmp/v-hidden-$cname" "/tmp/hidden-$cname.out" \
      -v github.com/gin-gonic/gin -test.run "$filter"; then
    n_hidden=$((n_hidden + 1))
  fi
done
if [ "$n_dirs" -ne 3 ]; then
  fail "expected exactly 3 hidden case directories, found $n_dirs"
fi
if [ "$n_hidden" -lt 2 ]; then
  fail "fewer than two hidden cases passed"
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0