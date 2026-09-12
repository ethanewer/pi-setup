#!/bin/bash
# Verifier for cistern-gate: an upstream-clone debugging task on pypa/pip.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# a requirement line with an invalid environment-marker section leaks
# pip._vendor.packaging.markers.InvalidMarker as a raw traceback instead of a
# clean InstallationError("Invalid requirement: ..."). The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, only the
#      minimal tracked source file is modified, nothing was deleted, no stray
#      files appeared inside the pip package, the fix changes the source, and
#      `import pip` resolves to the checked-out tree);
#   1. runs the project's own regression test for this bug, extracted at image
#      build time from the fix commit into /opt/golden/;
#   2. runs the project's own existing tests/unit/test_req.py from the tree,
#      proving the fix broke nothing else;
#   3. runs at least two authored hidden cases that exercise the same code
#      path from inputs the upstream test does not use (other invalid-marker
#      shapes must raise InstallationError, valid markers must still parse).
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=9d0e2601f8c82765b0fe92001540e9a7ddd4fdf1
FIX_SHA=95ef105f4eea913c09170dab3f4b6efebddf2843
FIX_FILE=src/pip/_internal/req/constructors.py
GOLDEN=/opt/golden/test_req.py

export PYTHONDONTWRITEBYTECODE=1

run_pytest () {  # run_pytest LABEL OUT ...args
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC" && python3 -m pytest "$@" -o addopts="" -q -p no:cacheprovider > "$out" 2>&1 ); then
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
  echo "ok: fix commit not present in the working clone"
fi

saw_mod=0
bad_tree=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  case "$line" in
    " M $FIX_FILE") saw_mod=1 ;;
    "?? "*) case "$line" in
              *__pycache__/*|*.pyc|*.pyo|.pytest_cache/*) : ;;
              *) echo "FAIL: unexpected untracked file: $line" >&2; bad_tree=1 ;;
            esac ;;
    *) echo "FAIL: unexpected working-tree change: $line" >&2; bad_tree=1 ;;
  esac
done <<< "$(git -C "$SRC" status --porcelain 2>/dev/null || true)"
if [ "$bad_tree" = 1 ]; then reward=0; else echo "ok: no unexpected working-tree changes"; fi
if [ "$saw_mod" = 0 ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2; reward=0
else
  echo "ok: $FIX_FILE is modified"
fi

pkg_new=$(git -C "$SRC" status --porcelain 2>/dev/null | grep '^?? src/pip/' | grep -v '__pycache__' || true)
if [ -n "$pkg_new" ]; then
  echo "FAIL: new files were added inside the pip package:" >&2
  printf '%s\n' "$pkg_new" | head -5 | sed 's/^/    /' >&2
  reward=0
fi

if ! ( cd / && python3 -c "import pip; import sys; sys.exit(0 if pip.__file__ == '$SRC/src/pip/__init__.py' else 3)" >/dev/null 2>&1 ); then
  echo "FAIL: 'import pip' does not resolve to the checked-out tree at /app/src" >&2
  reward=0
else
  echo "ok: import pip resolves to $SRC/src/pip/__init__.py"
fi

# ---------- 0b. isolated-mode behavioural check ---------------------------------
# The tree checks above and the pytest checks below run under a normal python,
# which imports sitecustomize and honours .pth files. An agent that never fixes
# the bug can install a sitecustomize hook or .pth sidecar in site-packages that
# intercepts install_req_from_line and converts InvalidMarker into
# InstallationError, which makes all the pytest-based checks pass while /app/src
# still contains the bug. Running the same behavioural contract under `python3 -S`
# (no site module: no sitecustomize, no .pth, no user site) makes the hook
# unreachable: the only code path left is the actual tree under /app/src.
cat > /tmp/isolated_check.py <<'PYEOF'
from pip._internal.req.constructors import install_req_from_line
from pip._internal.exceptions import InstallationError

bad = [
    'name; python_version == "1"; python_version == "2"',
    "foo; python_version == '3",
    'bar; (python_version == "3.10"',
]
for line in bad:
    try:
        install_req_from_line(line)
    except InstallationError as e:
        assert "Invalid requirement" in str(e), f"{line!r}: {e}"
    except Exception as e:
        raise SystemExit(f"{line!r}: wrong exception {type(e).__name__}: {e}")
    else:
        raise SystemExit(f"{line!r}: unexpectedly parsed")
req = install_req_from_line('ok; python_version == "3.12"')
assert str(req.markers) == 'python_version == "3.12"'
PYEOF
echo "== isolated-mode behavioural check (python3 -S, no startup hooks) =="
if ( cd / && PYTHONPATH="$SRC/src" python3 -S /tmp/isolated_check.py > /tmp/isolated.out 2>&1 ); then
  echo "ok: invalid markers raise InstallationError and valid markers parse (real tree, no hooks)"
else
  echo "FAIL: isolated-mode behaviour not satisfied (startup hooks cannot mask this)" >&2
  tail -30 /tmp/isolated.out | sed 's/^/    /' >&2
  reward=0
fi
rm -f /tmp/isolated_check.py /tmp/isolated.out

# ---------- 1. golden: the upstream regression test ---------------------------
echo "== golden test (upstream regression test for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
else
  run_pytest "golden test_markers_invalid" /tmp/golden.out \
    "$GOLDEN::TestInstallRequirement::test_markers_invalid" || true
fi

# ---------- 2. the project's own existing requirement-line suite --------------
echo "== the project's own existing tests/unit/test_req.py =="
run_pytest "existing tests/unit/test_req.py" /tmp/own.out \
  tests/unit/test_req.py || true

# ---------- 3. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  if ( cd "$SRC" && python3 -m pytest "$case" -o addopts="" -q -p no:cacheprovider > "$out" 2>&1 ); then
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