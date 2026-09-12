#!/bin/bash
# Verifier for cistern-flood: an upstream-clone debugging task on psf/requests.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# the no_proxy matcher exempts hosts that merely end with an entry and drops
# the bare-host match for dotted entries.  The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, the only
#      modified tracked file is the minimal source surface, and no new files
#      appeared inside the package);
#   1. runs the project's own regression test for this bug, extracted at
#      image build time from the fix commit into /opt/golden/;
#   2. runs the project's own existing proxy tests from tests/test_utils.py,
#      proving the fix broke nothing else;
#   3. runs three authored hidden cases (suffix-lookalike hosts, dotted /
#      port-pinned entries through the argument and the NO_PROXY environment
#      channels, and the end-to-end get_environ_proxies / resolve_proxies
#      path) that the upstream test does not cover.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=3816cfa1abd42dca21b9e837f26c59b246016aaf
FIX_SHA=a4f9a5999bdb9bf2d6e7c8aa973b28cacb17134f
GOLDEN=/opt/golden/pkg/test_utils.py
GOLDEN_NODE=test_should_bypass_proxies_no_proxy_domain_boundary
# Sha256 of the golden test EXACTLY as extracted from the fix commit at image
# build time (git blob of a4f9a599:tests/test_utils.py). The agent runs as
# root and /opt/golden lives in the shared container, so the file must be
# authenticated, not just checked for existence.
GOLDEN_SHA256=00d027432443a1aa9539c00a09550de9439cdd696d2e6acf2dc997de3a416946
# Interpreter / pytest shims that python would auto-import from the repo root.
# An untracked /app/src/pytest.py makes every `python3 -m pytest` exit 0
# without running a single test (verified: such a shim earned reward 1 here
# while the source bug stayed intact).
SHIM_BLOCK=(
  "$SRC/pytest.py"
  "$SRC/pytest"
  "$SRC/conftest.py"
  "$SRC/sitecustomize.py"
  "$SRC/usercustomize.py"
)

run_pytest () {  # run_pytest LABEL OUT ...args
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC" && python3 -m pytest "$@" -q -p no:cacheprovider -o addopts= > "$out" 2>&1 ); then
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
fi

porcelain=$(git -C "$SRC" status --porcelain --untracked-files=all 2>/dev/null || true)
bad=$(printf '%s\n' "$porcelain" | grep -v '^?? ' | grep -v '^ M src/requests/utils.py$' || true)
if [ -n "$bad" ]; then
  echo "FAIL: unexpected working-tree changes (only src/requests/utils.py may be modified):" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
fi
newpkg=$(printf '%s\n' "$porcelain" | grep '^?? src/requests/' | grep -v '__pycache__' | grep -v '\.pyc$' || true)
if [ -n "$newpkg" ]; then
  echo "FAIL: new files were added inside the requests package:" >&2
  printf '%s\n' "$newpkg" | head -5 | sed 's/^/    /' >&2
  reward=0
fi
if [ -z "$(git -C "$SRC" diff -- src/requests/utils.py 2>/dev/null || true)" ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2
  reward=0
fi

for shim in "${SHIM_BLOCK[@]}"; do
  if [ -e "$shim" ]; then
    echo "FAIL: forbidden auto-import shim present at $shim (item is not in the git tree but shadows python/pytest)" >&2
    reward=0
  fi
done
# No new modules at the repository root either: the fix is a modification of
# an existing tracked file, not a new package the interpreter could pick up.
for rootpy in "$SRC"/*.py; do
  [ -e "$rootpy" ] || continue
  if ! git -C "$SRC" ls-files --error-unmatch "$rootpy" >/dev/null 2>&1; then
    echo "FAIL: untracked python module at $rootpy would be auto-imported by the interpreter" >&2
    reward=0
  fi
done

# ---------- 1. golden: the upstream regression test ---------------------------
echo "== golden test (upstream regression test for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
elif [ "$(sha256sum "$GOLDEN" 2>/dev/null | awk '{print $1}')" != "$GOLDEN_SHA256" ]; then
  echo "FAIL: golden test has been modified (bytes differ from the fix-commit extraction; mean-cheating-by-editing-the-test is a scored 0)" >&2
  reward=0
else
  run_pytest "golden $GOLDEN_NODE" /tmp/golden.out "$GOLDEN::$GOLDEN_NODE" \
    || true
fi

# ---------- 2. the project's own existing proxy tests -------------------------
echo "== the project's own existing proxy tests =="
run_pytest "existing tests/test_utils.py proxy nodes" /tmp/own.out \
  tests/test_utils.py::test_select_proxies \
  tests/test_utils.py::test_should_bypass_proxies \
  tests/test_utils.py::test_should_bypass_proxies_no_proxy \
  tests/test_utils.py::test_should_bypass_proxies_pass_only_hostname \
  || true

# ---------- 2b. direct behavioral assertions (pytest-independent) -------------
echo "== direct behavioral assertions (not routed through pytest) =="
if ( cd "$SRC" && python3 /tests/assert_behavior.py > /tmp/behavior.out 2>&1 ); then
  echo "ok: direct behavioral assertions"
else
  echo "FAIL: direct behavioral assertions" >&2
  tail -20 /tmp/behavior.out | sed 's/^/    /' >&2
  reward=0
fi

# ---------- 3. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  if ( cd "$SRC" && python3 -m pytest "$case" -q -p no:cacheprovider -o addopts= > "$out" 2>&1 ); then
    echo "ok: hidden case $name"
  else
    echo "FAIL: hidden case $name" >&2
    tail -40 "$out" | sed 's/^/    /' >&2
    reward=0
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases were exercised" >&2; reward=0
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0