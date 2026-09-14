#!/bin/bash
# Verifier for dory-reach: an upstream-clone debugging task on
# aquasecurity/trivy.
#
# Bug (upstream issue #11050): the PEP 621 pyproject.toml dependency-list
# parser records each dependency name exactly as typed instead of PEP 503
# normalized, so 'Flask'/'typing_extensions'/'ruamel.yaml' are reported as
# such while poetry/pylock report 'flask'/'typing-extensions'/'ruamel-yaml'.
# The agent must write its own failing reproduction (repro_test.go +
# testdata/repro.toml, declared deliverables) and fix the real checkout at
# /app/src. The verifier:
#   0. asserts its own trust anchors. A root trial can substitute the
#      toolchain or the golden regression data (proven as an attack on the
#      sibling task with a stub /opt/go/bin/go); the sha256 of the go
#      binary and of the three golden files are hardcoded here and the
#      Dockerfile asserts the same values at image build.
#   1. asserts BLOB-LEVEL tree provenance: HEAD is still the pinned parent
#      commit, the fix commit is unreachable, exactly one commit is
#      reachable, every tracked file carries the parent's exact bytes except
#      the pyproject parser source (which must differ), nothing is staged,
#      and the only untracked files are the two reproduction deliverables.
#   2. runs the agent's OWN reproduction against the PARENT's parser source
#      (restored from the hash-pinned /opt/golden copy): it must FAIL with a
#      testify "Not equal" assertion mismatch - not a build error - proving
#      the reproduction is a genuine failing repro of this bug;
#   3. restores the agent's fixed parser source and runs the project's own
#      Python dependency parser suite with the FIX commit's regression test
#      and fixture overlaid (golden test, must pass);
#   4. runs the agent's reproduction again (must pass) plus two authored
#      hidden cases exercising the same code path from spellings the
#      upstream regression test does not use.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
# Declared deliverable paths (literal, as in task.toml and instruction.md).
REPRO_TEST=/app/src/pkg/dependency/parser/python/pyproject/repro_test.go
REPRO_FIXTURE=/app/src/pkg/dependency/parser/python/pyproject/testdata/repro.toml
PARENT_SHA=748a639b1d436a0566d325a4233ca13baf4cbd60
FIX_SHA=0012281c8a8adad2eff1889f12fe08a0ca5a7bfc
GOLDEN=/opt/golden
PKG=pkg/dependency/parser/python/pyproject

# Trust anchors. sha256 of /opt/go/bin/go as extracted from the pinned
# actions/go-versions tarball 1.26.3-25533533231, of the fix commit's
# pyproject_test.go and testdata/happy_v2.toml, and of the pristine parent's
# pyproject.go - all as extracted in the Dockerfile. The Dockerfile asserts
# these same values at build time (it fails the build if they ever drift), so
# the verifier constants and the image cannot silently disagree.
GO_BIN_SHA=d68b7abbc40d0844f673f6cf06ae3cded225c50437c6454fa37ef178d079fe65
GOLDEN_PT_SHA=59557e13b0f9ee4b213812d08655950f5eb85b0995fdacc6cc6900bd5da7976f
GOLDEN_TOML_SHA=ed5f54e532046c9fe971672216521e73e92643430ba83a27d3ae3892455528ff
PARENT_GO_SHA=cd6e2b9b5e9358a2fd4a32b9b7934cbcf1a62ee938071213ec9772f1d36bf4da

export PATH=/opt/go/bin:$PATH CGO_ENABLED=0 GOEXPERIMENT=jsonv2

python_scope_test () {  # python_scope_test LABEL OUT
  label="$1"; out="$2"
  if ( cd "$SRC" && go test -v -short ./pkg/dependency/parser/python/... > "$out" 2>&1 ); then
    if grep -qF "panic:" "$out"; then
      echo "FAIL: $label: run exited 0 but a runtime panic is present" >&2
      reward=0
      return 1
    fi
    if grep -q "FAIL" "$out"; then
      echo "FAIL: $label: run exited 0 but the log contains a FAIL line" >&2
      reward=0
      return 1
    fi
    echo "ok: $label"
    return 0
  fi
  echo "FAIL: $label: go test exited nonzero" >&2
  tail -60 "$out" | sed 's/^/    /' >&2
  reward=0
  return 1
}

# ---------- 0. trust anchors ------------------------------------------------
echo "== trust anchors =="
anchors_ok=1
if [ "$(sha256sum /opt/go/bin/go 2>/dev/null | cut -d' ' -f1)" = "$GO_BIN_SHA" ]; then
  echo "ok: go toolchain binary carries the pinned sha256"
else
  echo "FAIL: /opt/go/bin/go is not the pinned toolchain binary (substituted or wrapped)" >&2
  anchors_ok=0
fi
if [ "$(sha256sum "$GOLDEN/pyproject_test.go" 2>/dev/null | cut -d' ' -f1)" = "$GOLDEN_PT_SHA" ] && \
   [ "$(sha256sum "$GOLDEN/happy_v2.toml" 2>/dev/null | cut -d' ' -f1)" = "$GOLDEN_TOML_SHA" ] && \
   [ "$(sha256sum "$GOLDEN/parent_pyproject.go" 2>/dev/null | cut -d' ' -f1)" = "$PARENT_GO_SHA" ]; then
  echo "ok: golden regression test, fixture and pristine parent source carry the pinned sha256"
else
  echo "FAIL: /opt/golden files are missing or do not carry the pinned sha256" >&2
  anchors_ok=0
fi
if [ "$anchors_ok" != 1 ]; then
  echo "REWARD=0"
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi

# ---------- 1. tree provenance (blob-level) --------------------------------
echo "== tree provenance =="
bad=0

if [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" = "$PARENT_SHA" ]; then
  echo "ok: HEAD is the pinned parent commit"
else
  echo "FAIL: HEAD is not the pinned parent commit $PARENT_SHA" >&2; bad=1
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  echo "FAIL: the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)" >&2
  bad=1
else
  echo "ok: fix commit not present in the working clone"
fi

ncommits=$(git -C "$SRC" rev-list --all --count 2>/dev/null || echo -)
if [ "$ncommits" != "1" ]; then
  echo "FAIL: the working clone has '$ncommits' reachable commits; it must contain exactly the pinned parent commit (history was fetched or added)" >&2
  bad=1
else
  echo "ok: exactly one commit object reachable in the working clone"
fi

# Reproduction deliverables must exist and be the only untracked files.
if [ -f "$REPRO_TEST" ] && [ -s "$REPRO_TEST" ]; then
  echo "ok: reproduction test present ($REPRO_TEST)"
else
  echo "FAIL: reproduction test $REPRO_TEST is missing or empty (declared deliverable)" >&2
  bad=1
fi
if [ -f "$REPRO_FIXTURE" ] && [ -s "$REPRO_FIXTURE" ]; then
  echo "ok: reproduction fixture present ($REPRO_FIXTURE)"
else
  echo "FAIL: reproduction fixture $REPRO_FIXTURE is missing or empty (declared deliverable)" >&2
  bad=1
fi

# The project's own test file and fixture must be the PRistine parent bytes
# (the agent must not edit the tests to make the bug invisible).
if git -C "$SRC" cat-file -e "$PARENT_SHA:pkg/dependency/parser/python/pyproject/pyproject_test.go" 2>/dev/null \
   && git -C "$SRC" cat-file -e "$PARENT_SHA:pkg/dependency/parser/python/pyproject/testdata/happy_v2.toml" 2>/dev/null; then
  echo "ok: parent tree provides the baseline test file and fixture"
else
  echo "FAIL: could not resolve the parent baseline test files" >&2
  bad=1
fi

# BLOB- AND FLAG-LEVEL provenance: worktree bytes are compared with the
# parent TREE using git's own normalization (git diff against the parent
# commit), and every assume-unchanged/skip-worktree bit the agent may have
# set is cleared first so a dirty file cannot be hidden from the diff.
flagged=0
while IFS= read -r line; do
  mode=$(printf '%s' "$line" | cut -c1)
  path=${line:2}
  case "$mode" in
    [a-z] | S)
      git -C "$SRC" update-index --no-assume-unchanged --no-skip-worktree -- "$path" 2>/dev/null || true
      flagged=1 ;;
  esac
done < <(git -C "$SRC" ls-files -v)
if [ "$flagged" = 1 ]; then
  echo "ok: cleared assume-unchanged/skip-worktree bits set in the working clone"
fi

dirty=$(git -C "$SRC" diff --name-only "$PARENT_SHA" -- 2>/dev/null || true)
saw_fix=0
out_of_scope=0
if [ -n "$dirty" ]; then
  while IFS= read -r f; do
    case "$f" in
      "$PKG/pyproject.go") saw_fix=1 ;;
      *) echo "FAIL: out-of-scope modified or deleted tracked file: $f" >&2; out_of_scope=1 ;;
    esac
  done <<< "$dirty"
fi
if [ "$saw_fix" = 1 ]; then
  echo "ok: the pyproject parser source differs from the parent (fix implemented)"
else
  echo "FAIL: the pyproject parser source is unmodified (no fix implemented)" >&2
  bad=1
fi
[ "$out_of_scope" = 1 ] && bad=1

staged=$(git -C "$SRC" diff --cached --name-only "$PARENT_SHA" -- 2>/dev/null || true)
if [ -n "$staged" ]; then
  echo "FAIL: staged changes vs the parent: $staged (nothing may be staged)" >&2
  bad=1
else
  echo "ok: no staged changes"
fi

# Untracked files: exactly the two reproduction deliverables may exist.
extra=0
while IFS= read -r -d '' f; do
  case "$f" in
    "$PKG/repro_test.go" | "$PKG/testdata/repro.toml") : ;;
    *) echo "FAIL: unexpected untracked file inside the repository: $f" >&2; extra=1 ;;
  esac
done < <(git -C "$SRC" ls-files --others --exclude-standard -z)
[ "$extra" = 0 ] || bad=1
[ "$bad" = 1 ] && reward=0

echo "REWARD=$reward"

# ---------- 2. the agent's reproduction against the PARENT's source ---------
# Restore the pristine parent parser source (hash-pinned in /opt/golden) and
# run the agent's own reproduction: it must FAIL with a testify "Not equal"
# assertion mismatch, not with a build error. A reproduction that would pass
# on the buggy code, or that fails to build, earns 0.
echo "== agent's reproduction vs the parent's parser source =="
if [ "$reward" = 1 ]; then
  repro_func=$(grep -oE 'func Test[A-Za-z0-9_]+' "$REPRO_TEST" 2>/dev/null | head -1 | awk '{print $2}')
  if [ -z "$repro_func" ]; then
    echo "FAIL: no testify test function (func TestXxx) found in $PKG/repro_test.go" >&2
    reward=0
  fi
fi
if [ "$reward" = 1 ]; then
  cp "$SRC/$PKG/pyproject.go" /tmp/agent_pyproject.go || { echo "FAIL: could not save the agent's parser source" >&2; reward=0; }
fi
if [ "$reward" = 1 ]; then
  if cp "$GOLDEN/parent_pyproject.go" "$SRC/$PKG/pyproject.go" \
     && ! ( cd "$SRC" && go test -v -short ./pkg/dependency/parser/python/... > /tmp/repro_pre.log 2>&1 ); then
    if grep -qF "Not equal" /tmp/repro_pre.log && grep -qF "=== RUN   $repro_func" /tmp/repro_pre.log \
       && ! grep -q "setup failed" /tmp/repro_pre.log; then
      echo "ok: reproduction fails against the parent's source with a testify assertion mismatch"
    else
      echo "FAIL: reproduction does not fail against the parent's source in the required way" >&2
      echo "      required: 'Not equal' + a RUN line for $repro_func, and no build error" >&2
      grep -E "=== RUN|setup failed|Not equal|error:" /tmp/repro_pre.log | head -20 | sed 's/^/    /' >&2
      reward=0
    fi
  else
    echo "FAIL: reproduction unexpectedly passes (or the scope fails to build) against the parent's source" >&2
    tail -40 /tmp/repro_pre.log 2>/dev/null | sed 's/^/    /' >&2
    reward=0
  fi
  cp /tmp/agent_pyproject.go "$SRC/$PKG/pyproject.go" || { echo "FAIL: could not restore the agent's parser source" >&2; reward=0; }
fi

# ---------- 3. golden test + the project's own pyproject parser suite -------
# Overlay the FIX commit's regression test and fixture exactly as the mining
# reproduction did, and require the whole Python parser scope to pass on the
# agent's repaired tree.
if [ "$reward" = 1 ]; then
  echo "== golden test + the project's own python parser suite =="
  cp "$GOLDEN/pyproject_test.go" "$SRC/$PKG/pyproject_test.go"
  cp "$GOLDEN/happy_v2.toml" "$SRC/$PKG/testdata/happy_v2.toml"
  python_scope_test "project's own python parser suite incl. the upstream regression test" /tmp/golden_fixed.out || true
  if [ "$reward" = 1 ] && ! grep -qF "=== RUN   TestParser_Parse/happy_path_v2" /tmp/golden_fixed.out; then
    echo "FAIL: the upstream regression case happy_path_v2 did not execute" >&2
    reward=0
  fi
fi

# ---------- 4. hidden cases + the agent's reproduction (repaired tree) ------
if [ "$reward" = 1 ]; then
  echo "== hidden cases =="
  n_hidden=0
  for case in /tests/hidden/*/; do
    [ -d "$case" ] || continue
    n_hidden=$((n_hidden + 1))
    name=$(basename "$case")
    ok_copy=1
    mkdir -p "$SRC/$PKG/testdata" || ok_copy=0
    cp "$case"/*_test.go "$SRC/$PKG/" 2>/dev/null || ok_copy=0
    cp "$case"/testdata/*.toml "$SRC/$PKG/testdata/" 2>/dev/null || ok_copy=0
    if [ "$ok_copy" = 0 ]; then
      echo "FAIL: could not stage hidden case $name into the tree" >&2
      reward=0
      continue
    fi
    fname=$(ls "$case"/*_test.go 2>/dev/null | head -1)
    func=$(grep -oE 'func Test[A-Za-z0-9_]+' "$fname" 2>/dev/null | head -1 | awk '{print $2}')
    out="/tmp/hidden-$name.out"
    python_scope_test "hidden case $name" "$out" || true
    if [ -n "$func" ] && ! grep -qF "=== RUN   $func" "$out"; then
      echo "FAIL: hidden case $name did not execute (no RUN line for $func in the test log)" >&2
      reward=0
    fi
  done
  if [ "$n_hidden" -lt 2 ]; then
    echo "FAIL: fewer than two hidden cases were exercised" >&2
    reward=0
  fi
fi

if [ "$reward" = 1 ]; then
  echo "== agent's reproduction against the repaired tree =="
  if python_scope_test "agent's reproduction (repaired tree)" /tmp/repro_post.out \
     && grep -qF "=== RUN   $repro_func" /tmp/repro_post.out; then
    echo "ok: reproduction passes against the repaired tree"
  else
    echo "FAIL: reproduction does not pass against the repaired tree" >&2
    reward=0
  fi
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0