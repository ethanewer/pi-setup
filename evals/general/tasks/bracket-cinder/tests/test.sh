#!/bin/bash
# Verifier for bracket-cinder: an upstream-clone debugging task on gallery-dl.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# formatted keyword values that mix literal text with {placeholders} crash
# with "TypeError: sequence item N: expected str instance, X found" whenever a
# placeholder resolves to a non-text value.  The verifier:
#   0. asserts the Python interpreter tree and /opt/golden still match the
#      build-time manifest (no sitecustomize.py/.pth/interpreter hook, no
#      tampered pytest or golden test wants in), then tree provenance (HEAD
#      is still the pinned parent commit, the upstream fix commit is not
#      reachable from the working clone, only the minimal tracked source file
#      is modified, and no new files appeared inside the package or anywhere
#      else in the tree except inert cache artifacts);
#   1. checks /opt/golden/test_formatter.py is byte-identical to the
#      upstream test file at the fix commit, and runs that upstream
#      regression test with the project's own test runner;
#   2. runs the project's own existing suites (its own copy of the formatter
#      tests plus the dt and text modules' self-contained suites), proving the
#      fix broke nothing else;
#   3. runs three authored hidden cases (keywords-eval-style templates with
#      int/None/datetime placeholders, custom fmt functions the upstream test
#      does not use, and regressions guards) that the upstream test does not
#      cover.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=f77c330d83018b25924d219f96aaf4f064bd3eaf
FIX_SHA=098fbba8d7eef0e164b1dadbbf459002c68347e8
GOLDEN=/opt/golden/test_formatter.py
GOLDEN_SHA256=2f7cbfaae57b6d89e1a78edc7ae0094c0856f282cf3cedbafd5b4d27afd1fa53
INTERP_MANIFEST=/tests/system-manifest.sha256

run_pytest () {  # run_pytest LABEL OUT ...args
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC" && python3 -m pytest "$@" -q -p no:cacheprovider > "$out" 2>&1 ); then
    echo "ok: $label"
    return 0
  fi
  echo "FAIL: $label" >&2
  tail -40 "$out" | sed 's/^/    /' >&2
  reward=0
  return 1
}

# ---------- 0a. interpreter integrity: no interception wrapper can hide here --
# The agent runs as root in this harness, so a planted sitecustomize.py / a
# patched _pytest / a golden-test swap would make an untouched buggy tree pass
# its own pytest gates.  /tests is uploaded only after the agent phase and is
# the only tree the agent cannot modify, so the build-time manifest of every
# file the interpreter can load (plus /opt/golden and the python binaries) is
# kept there and re-checked before anything runs.
echo "== interpreter integrity (build-time manifest) =="
gen_manifest () {
  {
    find /usr/local/lib/python3.12 -type f ! -path '*/__pycache__/*' -print0 \
      | sort -z | xargs -0 sha256sum
    find -L /usr/local/bin /usr/bin -maxdepth 1 -type f \( -name 'python*' -o -name 'pytest*' \) -print0 \
      | sort -z | xargs -0 sha256sum
    find /opt/golden -type f ! -path '*/__pycache__/*' -print0 \
      | sort -z | xargs -0 sha256sum
  }
}
if [ ! -s "$INTERP_MANIFEST" ]; then
  echo "FAIL: interpreter manifest missing from harness tests dir" >&2; reward=0
elif ! gen_manifest > /tmp/now-manifest.txt 2>/dev/null; then
  echo "FAIL: could not regenerate the interpreter manifest" >&2; reward=0
elif ! diff -u "$INTERP_MANIFEST" /tmp/now-manifest.txt > /tmp/manifest.diff 2>&1; then
  echo "FAIL: the Python interpreter tree, the python binaries or /opt/golden differ from the build-time manifest (an interception wrapper or a tampered golden test was left behind):" >&2
  head -12 /tmp/manifest.diff | sed 's/^/    /' >&2
  reward=0
else
  echo "ok: interpreter tree, python binaries and /opt/golden match the build-time manifest"
fi

# ---------- 0b. tree provenance -----------------------------------------------
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

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
# Only gallery_dl/formatter.py may be modified. Untracked entries are rejected
# except inert cache/bytecode artifacts that an honest agent's tooling or the
# test runner itself leaves behind (.pytest_cache/, __pycache__/, .pyc, .pyo,
# .coverage, .mypy_cache/, .ruff_cache/ -- none of these are executed by the
# verifier). Anything else -- a conftest.py, a pytest.ini, a helper module, a
# scratch script inside the clone -- fails the task.
bad=$(printf '%s\n' "$porcelain" \
  | grep -v '^ M gallery_dl/formatter.py$' \
  | grep -v -e '^?? \.pytest_cache/' \
            -e '^?? __pycache__/' \
            -e '^?? .*/__pycache__/' \
            -e '\.pyc$' \
            -e '\.pyo$' \
            -e '^?? \.coverage$' \
            -e '^?? \.mypy_cache/' \
            -e '^?? \.ruff_cache/' \
  || true)
if [ -n "$bad" ]; then
  echo "FAIL: unexpected working-tree changes (only gallery_dl/formatter.py may be modified; no other file may be added, deleted, renamed or staged inside the clone):" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
fi
newpkg=$(printf '%s\n' "$porcelain" | grep '^?? gallery_dl/' || true)
if [ -n "$newpkg" ]; then
  echo "FAIL: new files were added inside the gallery_dl package:" >&2
  printf '%s\n' "$newpkg" | head -5 | sed 's/^/    /' >&2
  reward=0
fi
if [ -z "$(git -C "$SRC" diff -- gallery_dl/formatter.py 2>/dev/null || true)" ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2
  reward=0
fi

# the fix must actually change the modified module: require the golden,
# existing-suite and hidden-case runs below to pass (behavioral verdict),
# we do not pin the exact implementation.

# ---------- 1. golden: the upstream regression test ---------------------------
echo "== golden test (upstream regression test for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
elif [ "$(sha256sum "$GOLDEN" 2>/dev/null | awk '{print $1}')" != "$GOLDEN_SHA256" ]; then
  echo "FAIL: /opt/golden/test_formatter.py does not match the fix-commit bytes (it was tampered with or the image was rebuilt)" >&2; reward=0
else
  run_pytest "golden test/test_formatter.py (fix-commit copy)" /tmp/golden.out \
    "$GOLDEN" || true
fi

# ---------- 2. the project's own existing suites ------------------------------
echo "== the project's own existing tests =="
run_pytest "existing test/test_formatter.py (parent copy, 42 tests)" \
  /tmp/own-fmt.out test/test_formatter.py || true
run_pytest "existing test/test_dt.py and test/test_text.py" \
  /tmp/own-dt.out test/test_dt.py test/test_text.py || true

# ---------- 3. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  if ( cd "$SRC" && python3 -m pytest "$case" -q -p no:cacheprovider > "$out" 2>&1 ); then
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