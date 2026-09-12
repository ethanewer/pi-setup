#!/bin/bash
# Verifier for bracket-cleat: an upstream-clone debugging task on click.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# an option declared is_flag=False together with an explicit flag_value and a
# default is refused when the option name is passed with no value ("Option
# '--name' requires an argument.", exit code 2), where the intended behaviour
# is that such an option acts as a valueless flag (flag_value is used) while
# an explicit value is still accepted. The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, only the
#      minimal tracked source file is modified, no new files appeared inside
#      the library package, the imported click is the editable one, and the
#      upstream regression test was not copied into the tree);
#   1. runs the project's own regression tests for this bug, extracted at
#      image build time from the fix commit into /opt/golden/;
#   2. runs the project's own existing option/argument/basic suites from the
#      tree, proving the fix broke nothing else;
#   3. runs at least two authored hidden cases (short-option and attached
#      forms, type-converted flag_value and multiple=True mixing bare and
#      explicit values, and a valueless flag among positional arguments)
#      that the upstream test does not cover.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=7f7bbe4569ea68e8dabee232eade069ef3310aea
FIX_SHA=91de59c6c8abc8251e7af551cd4546cc964288af
GOLDEN=/opt/golden/test_options.py
# sha256 of tests/test_options.py extracted from the fix commit at image
# build time (git show 91de59c...:tests/test_options.py). Re-checked here
# because the trial runs as root and the golden file lives in the image's
# writable layer: replacing it with a trivially-passing copy would fake the
# regression gate while leaving the bug in place.
GOLDEN_SHA256=c37b87051ff74165f3892fb6fc9db0505773a2649d8cb820674e7f4dc870155e
PROBE=/tests/probe_no_site.py

run_pytest () {  # run_pytest LABEL OUT ...args
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC" && python3 -m pytest "$@" -q -p no:cacheprovider > "$out" 2>&1 ); then
    echo "ok: $label"
    return 0
  fi
  echo "FAIL: $label" >&2
  tail -60 "$out" | sed 's/^/    /' >&2
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

if ! python3 -c 'import click; assert click.__file__.startswith("/app/src/"), click.__file__' 2>/dev/null; then
  echo "FAIL: import click does not resolve to the editable checkout at /app/src (package was replaced?)" >&2
  python3 -c 'import click; print("    click imported from:", click.__file__)' 2>&1 | head -2 >&2
  reward=0
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
bad=$(printf '%s\n' "$porcelain" | grep -v '^ M src/click/core.py$' | grep -v '^?? ' || true)
if [ -n "$bad" ]; then
  echo "FAIL: unexpected working-tree changes (only src/click/core.py may be modified):" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
fi
newpkg=$(printf '%s\n' "$porcelain" | grep '^?? src/' || true)
if [ -n "$newpkg" ]; then
  echo "FAIL: new files were added inside the library package src/:" >&2
  printf '%s\n' "$newpkg" | head -5 | sed 's/^/    /' >&2
  reward=0
fi
if [ -z "$(git -C "$SRC" diff -- src/click/core.py 2>/dev/null || true)" ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2
  reward=0
fi
if [ -f "$SRC/tests/test_options.py" ] && grep -q "test_flag_value_optional_behavior" "$SRC/tests/test_options.py" 2>/dev/null; then
  echo "FAIL: the upstream regression test was copied into the working tree (only the source repair is allowed)" >&2
  reward=0
fi

# ---------- 0.5 the decisive behaviour check in a site-free interpreter ------ 
# The trial runs as root, so anything in the image (or in site-packages) can be
# monkeypatched. This probe re-derives the required behaviour straight from
# /app/src/src with `python3 -S`, which skips sitecustomize.py and every .pth
# shim, so it can only pass if the checked-out source itself behaves correctly.
# The probe is shipped under /tests and re-uploaded pristine at verify time,
# so it cannot be forged by editing the tree or the image.
echo "== decisive probe in a site-free interpreter (python3 -S) =="
if [ ! -s "$PROBE" ]; then
  echo "FAIL: probe fixture missing from /tests" >&2; reward=0
elif ( cd /tmp && PYTHONPATH="$SRC/src" python3 -S "$PROBE" > /tmp/probe-nosite.out 2>&1 ); then
  echo "ok: site-free probe from the real source passed"
else
  echo "FAIL: probe from the real source failed (the tree does not behave as fixed)" >&2
  tail -10 /tmp/probe-nosite.out | sed 's/^/    /' >&2
  reward=0
fi

# Harness-owned dirs are re-uploaded pristine before the verifier runs, but
# sweep conftest.py from earlier in the trial so no collection-time shim can
# be picked up by pytest below.
find /opt/golden /tests -name 'conftest.py' -delete 2>/dev/null || true

# ---------- 1. golden: the upstream regression tests -------------------------
echo "== golden tests (upstream regression tests for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test file missing from image" >&2; reward=0
elif [ "$(sha256sum "$GOLDEN" | cut -d' ' -f1)" != "$GOLDEN_SHA256" ]; then
  echo "FAIL: /opt/golden/test_options.py does not match the upstream fix-commit extraction (was it replaced?)" >&2
  reward=0
else
  run_pytest "golden test_flag_value_optional_behavior" /tmp/golden1.out \
    "$GOLDEN::test_flag_value_optional_behavior" || true
  run_pytest "golden test_flag_value_with_type_conversion" /tmp/golden2.out \
    "$GOLDEN::test_flag_value_with_type_conversion" || true
fi

# ---------- 2. the project's own existing suites -----------------------------
echo "== the project's own existing suites =="
run_pytest "existing tests/test_options.py" /tmp/own-opt.out tests/test_options.py \
  || true
run_pytest "existing tests/test_arguments.py" /tmp/own-arg.out tests/test_arguments.py \
  || true
run_pytest "existing tests/test_basic.py" /tmp/own-basic.out tests/test_basic.py \
  || true

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
    tail -60 "$out" | sed 's/^/    /' >&2
    reward=0
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases were exercised" >&2; reward=0
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0