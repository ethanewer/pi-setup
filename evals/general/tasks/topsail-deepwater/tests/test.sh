#!/bin/bash
# Verifier for topsail-deepwater: prometheus promtool TSDB dump drops the
# earliest samples of histogram series (upstream bug #18051).
#
# The agent must: author a failing reproduction (/app/repro.sh) that drives the
# project's own test runner, then fix the dump source in /app/src so the
# reproduction, the project's own regression tests, its existing promtool
# suite, and this task's hidden cases all pass. The verifier:
#   0. asserts provenance: HEAD is the pinned parent commit, the upstream fix
#      commit is not reachable from the clone, the only difference from the
#      pinned commit is the minimal source fix, the overlaid/golden test files
#      are byte-identical to their pinned originals, and /app/repro.sh exists,
#      is executable, and invokes the project's own test runner;
#   1. runs the agent's reproduction against the PRE-FIX tree (dump source
#      restored to the pinned version): it must FAIL and print a failing test
#      run;
#   2. runs the agent's reproduction against the repaired tree: it must PASS;
#   3. runs the project's own upstream regression tests (extracted at build
#      time into /opt/golden) against the repaired tree, then the whole
#      cmd/promtool module suite with the upstream test file (the fix-commit
#      CI shape), then the whole module suite with the ORIGINAL parent test
#      file (the fix must break nothing);
#   4. runs two authored hidden cases exercising the same code path from
#      inputs the upstream tests do not use.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=6f81b2271a90887048f209298382340d61f35faf
FIX_SHA=94ddb36f647b9b50dee4ce06da27a1239e59ffcc
GOLDEN=/opt/golden/tsdb_test.go
GOLDEN_SHA=85d378ec420dac96e6768e20a949ae0c2b743241536cd10a953217b86b29b107
PARENT_TEST_SHA=5f02e825b4cdfc953c8a76eb1149d06de3d75f54e903a74ca05657425490685a

run_go_test () {  # run_go_test LABEL OUT ...args  -- runs `go test` in $SRC
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC" && go test -v "$@" > "$out" 2>&1 ); then
    echo "ok: $label"
    return 0
  fi
  echo "FAIL: $label" >&2
  tail -30 "$out" | sed 's/^/    /' >&2
  reward=0
  return 1
}

# ---------- 0. tree provenance -----------------------------------------------
echo "== provenance =="
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
  echo "ok: the upstream fix commit is not present in the clone"
fi

if [ -z "$(git -C "$SRC" diff -- cmd/promtool/tsdb.go 2>/dev/null || true)" ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2
  reward=0
else
  echo "ok: cmd/promtool/tsdb.go differs from the pinned commit"
fi

# Semantic gate: the fix must exist in the source. Extract the body of
# formatSeriesSet (the dump renderer) and require that (a) the buggy
# per-type loop pattern is GONE and (b) an explicit unknown-sample-type error
# is reported. The parent body contains the triple loop and no such error, so
# neither check can pass on an unfixed tree. (Other formatters elsewhere in
# the file legitimately keep their own loops, so the gate is scoped to the
# renderer's body only.)
fs_body=$(sed -n '/^func formatSeriesSet(ss storage.SeriesSet) error {/,/^}/p' "$SRC/cmd/promtool/tsdb.go" 2>/dev/null || true)
if printf '%s\n' "$fs_body" | grep -q 'for it.Next() == chunkenc.Val'; then
  echo "FAIL: the buggy per-type loop pattern is still present in formatSeriesSet" >&2
  reward=0
elif printf '%s\n' "$fs_body" | grep -q 'unknown sample type'; then
  echo "ok: formatSeriesSet no longer re-advances the iterator per type and reports unknown sample types"
else
  echo "FAIL: no explicit unknown-sample-type handling found in formatSeriesSet" >&2
  reward=0
fi

tree_test_sha=$(sha256sum < "$SRC/cmd/promtool/tsdb_test.go" 2>/dev/null | cut -d' ' -f1)
if [ "$tree_test_sha" = "$PARENT_TEST_SHA" ]; then
  echo "ok: cmd/promtool/tsdb_test.go is byte-identical to the pinned parent version"
else
  echo "FAIL: cmd/promtool/tsdb_test.go was altered (${tree_test_sha:-missing}); the agent may not touch the existing tests" >&2
  reward=0
fi

golden_sha=$(sha256sum < "$GOLDEN" 2>/dev/null | cut -d' ' -f1)
if [ "$golden_sha" = "$GOLDEN_SHA" ]; then
  echo "ok: /opt/golden/tsdb_test.go is byte-identical to the upstream regression test"
else
  echo "FAIL: /opt/golden/tsdb_test.go was altered (${golden_sha:-missing})" >&2
  reward=0
fi

if [ ! -f /app/repro.sh ]; then
  echo "FAIL: /app/repro.sh does not exist" >&2; reward=0
elif [ ! -x /app/repro.sh ]; then
  echo "FAIL: /app/repro.sh is not executable" >&2; reward=0
else
  echo "ok: /app/repro.sh exists and is executable"
fi
if [ -f /app/repro.sh ] && ! grep -q 'go test' /app/repro.sh; then
  echo "FAIL: /app/repro.sh never invokes the project's own test runner (\`go test\`)" >&2
  reward=0
else
  echo "ok: /app/repro.sh drives the project's own test runner"
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
bad=$(printf '%s\n' "$porcelain" |
      grep -v '^ M cmd/promtool/tsdb.go$' || true)
if [ -n "$bad" ]; then
  echo "FAIL: unexpected working-tree changes (only cmd/promtool/tsdb.go may differ):" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
else
  echo "ok: no other tracked or untracked changes in the repository"
fi

# ---------- 1. agent repro against the PRE-FIX tree (must fail) ---------------
echo "== agent reproduction against the pre-fix tree =="
if [ -f /app/repro.sh ] && [ -x /app/repro.sh ]; then
  if ! cp "$SRC/cmd/promtool/tsdb.go" /tmp/agent-tsdb.go 2>/dev/null; then
    echo "FAIL: cannot snapshot the agent's dump source" >&2
    reward=0
  fi
  if git -C "$SRC" checkout HEAD -- cmd/promtool/tsdb.go >/dev/null 2>&1; then
    if bash /app/repro.sh > /tmp/repro-prefix.out 2>&1; then
      echo "FAIL: the agent's reproduction PASSED on the pre-fix tree; it does not detect the bug" >&2
      reward=0
    else
      if grep -q 'FAIL' /tmp/repro-prefix.out; then
        echo "ok: the agent reproduction fails on the pre-fix tree with a failing test run"
      else
        echo "FAIL: the agent reproduction failed on the pre-fix tree but without a failing go test run; it is not a behavioural reproduction" >&2
        reward=0
      fi
    fi
  else
    echo "FAIL: could not restore the pre-fix dump source" >&2
    reward=0
  fi
  if [ -f /tmp/agent-tsdb.go ]; then
    cp /tmp/agent-tsdb.go "$SRC/cmd/promtool/tsdb.go"
  fi
fi

# ---------- 2. agent repro against the repaired tree (must pass) --------------
echo "== agent reproduction against the repaired tree =="
if [ -f /app/repro.sh ] && [ -x /app/repro.sh ]; then
  if bash /app/repro.sh > /tmp/repro-fixed.out 2>&1; then
    if grep -q 'PASS' /tmp/repro-fixed.out; then
      echo "ok: the agent reproduction passes on the repaired tree"
    else
      echo "FAIL: the agent reproduction passed on the repaired tree but without a passing go test run" >&2
      reward=0
    fi
  else
    echo "FAIL: the agent reproduction failed on the repaired tree" >&2
    tail -30 /tmp/repro-fixed.out | sed 's/^/    /' >&2
    reward=0
  fi
fi

# ---------- 3. golden + project suites ----------------------------------------
echo "== upstream regression tests (extracted at build time) =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
else
  cp "$GOLDEN" "$SRC/cmd/promtool/tsdb_test.go"
  run_go_test "golden TestTSDBDumpNativeHistogram" /tmp/golden1.out \
    ./cmd/promtool -run TestTSDBDumpNativeHistogram || true
  run_go_test "golden TestFormatSeriesSetRejectsUnknownSampleType" /tmp/golden2.out \
    ./cmd/promtool -run TestFormatSeriesSetRejectsUnknownSampleType || true
  run_go_test "whole cmd/promtool module suite with the upstream test file" /tmp/goldensuite.out \
    ./cmd/promtool || true
  git -C "$SRC" checkout -- cmd/promtool/tsdb_test.go >/dev/null 2>&1
fi

echo "== the project's own existing promtool suite (original test file) =="
run_go_test "whole cmd/promtool module suite with the original parent test file" /tmp/ownsuite.out \
  ./cmd/promtool || true

after=$(sha256sum < "$SRC/cmd/promtool/tsdb_test.go" 2>/dev/null | cut -d' ' -f1)
if [ "$after" != "$PARENT_TEST_SHA" ]; then
  echo "FAIL: cmd/promtool/tsdb_test.go was not restored to the pinned version after the golden runs" >&2
  reward=0
fi

# ---------- 4. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  copied=""
  for f in "$case"*.go; do
    [ -f "$f" ] || continue
    dst="$SRC/cmd/promtool/zzhidden_${name}_$(basename "$f")"
    if cp -p "$f" "$dst" 2>/dev/null; then
      copied="$copied $dst"
    else
      echo "FAIL: cannot place hidden case $name into the tree" >&2
      reward=0
    fi
  done
  out="/tmp/hidden-${name}.out"
  if ( cd "$SRC" && go test -v ./cmd/promtool -run TestHidden > "$out" 2>&1 ); then
    echo "ok: hidden case $name"
  else
    echo "FAIL: hidden case $name" >&2
    tail -30 "$out" | sed 's/^/    /' >&2
    reward=0
  fi
  for d in $copied; do rm -f "$d"; done
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases were exercised" >&2; reward=0
fi

# ---------- 5. tree clean again after the hidden-case runs -------------------
post=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
extra=$(printf '%s\n' "$post" |
        grep -v '^ M cmd/promtool/tsdb.go$' || true)
if [ -n "$extra" ]; then
  echo "FAIL: hidden-case cleanup did not restore the tree:" >&2
  printf '%s\n' "$extra" | head -5 | sed 's/^/    /' >&2
  reward=0
else
  echo "ok: tree restored after hidden-case runs"
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0