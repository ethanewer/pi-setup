#!/bin/bash
# Verifier for cistern-dune: an upstream-clone debugging task on pallets/click.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# FuncParamType.convert discards the message of the ValueError raised by the
# wrapped conversion function and echoes the raw input value back in the
# resulting BadParameter error.  The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, only the
#      minimal tracked source file is modified, and no new files appeared
#      inside the package);
#   0b. asserts the fix lives in the tree source itself: a python -S probe
#      imports click from /app/src with site hooks disabled and exercises the
#      ValueError path directly, so sitecustomize/.pth/conftest wrappers or a
#      rewritten /opt/golden cannot fake a fix;
#   1. runs the project's own regression test for this bug, extracted at image
#      build time from the fix commit into /opt/golden/;
#   2. runs the project's own entire existing test suite from the tree,
#      proving the fix broke nothing else;
#   3. runs three authored hidden cases (full CLI invocation, non-string input
#      value, exact message preservation on bytes input) that the upstream
#      test does not cover.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

# Scrub interpreter-level contamination before anything else runs. The trial
# agent runs as root in this image, so it could drop a sitecustomize.py or a
# .pth file into site-packages, rewrite /opt/golden, or shadow the editable
# install with a fake `click` package in site-packages -- all outside the git
# tree, so none of them show up in `git status`. Every check below that must
# see the REAL tree runs under `python3 -S` (no site import, no .pth, no
# sitecustomize/usercustomize), with click imported straight from /app/src/src.
unset PYTHONPATH PYTHONSTARTUP PYTHONHOME 2>/dev/null || true

SRC=/app/src
PARENT_SHA=5b9630f50fde938b72ad8c99542efe3a6f5717e2
FIX_SHA=fc6c7c47edd6110b6bd5a1a5297b2035214b0cd1
GOLDEN=/opt/golden/test_types.py
PTCFG="$SRC/pyproject.toml"

run_pytest () {  # run_pytest LABEL OUT ...args
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC" && python3 -m pytest "$@" -c "$PTCFG" -q -p no:cacheprovider > "$out" 2>&1 ); then
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

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
bad=$(printf '%s\n' "$porcelain" | grep -v '^ M src/click/types.py$' | grep -v '^?? ' || true)
if [ -n "$bad" ]; then
  echo "FAIL: unexpected working-tree changes (only src/click/types.py may be modified):" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
fi
newpkg=$(printf '%s\n' "$porcelain" | grep '^?? src/click/' || true)
if [ -n "$newpkg" ]; then
  echo "FAIL: new files were added inside the click package:" >&2
  printf '%s\n' "$newpkg" | head -5 | sed 's/^/    /' >&2
  reward=0
fi
if [ -z "$(git -C "$SRC" diff -- src/click/types.py 2>/dev/null || true)" ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2
  reward=0
fi

# ---------- 0b. semantic check: the fix must live in the tree itself ----------
# This is the load-bearing anti-bypass check. It runs python with -S so no
# sitecustomize, usercustomize, .pth or other site hook the agent planted can
# intercept, imports click straight from the checked-out tree, and exercises
# the ValueError path directly. A wrapper that makes pytest pass while the
# source stays buggy fails here.
sem_out=$(cd "$SRC" && python3 -S - "$SRC" <<'PY' 2>&1
import sys
sys.path.insert(0, sys.argv[1] + "/src")
import click


def param(exc):
    def parse(value):
        raise exc

    return click.types.FuncParamType(parse)


checks = [
    (ValueError("bad value: nope"), "nope", "bad value: nope"),
    (ValueError(), "nope", "nope"),
    (ValueError("must be a positive integer"), 1729, "must be a positive integer"),
    (ValueError(), 1729, "1729"),
    (ValueError("invalid, cannot parse"), b"raw bytes", "invalid, cannot parse"),
]
for exc, value, expected in checks:
    try:
        param(exc).convert(value, None, None)
    except click.BadParameter as e:
        if expected not in e.message:
            print(f"MISS: {exc!r} on {value!r} -> message {e.message!r}, wanted {expected!r}")
            raise SystemExit(1)
        continue
    print(f"MISS: {exc!r} on {value!r} raised nothing")
    raise SystemExit(1)
print("semantic ok: FuncParamType surfaces the ValueError message from the tree source")
PY
)
if [ $? -eq 0 ]; then
  echo "ok: semantic check (tree source itself implements the fix)"
else
  echo "FAIL: semantic check -- the tree source does not implement the fix:" >&2
  printf '%s\n' "$sem_out" | sed 's/^/    /' >&2
  reward=0
fi

# ---------- 1. golden: the upstream regression test ---------------------------
echo "== golden test (upstream regression test for this bug) =="
GOLDEN_HASH=f64e15d2a65b0621ba6be87236eff4c1ffd6fe616c299bc40cbf5bc58f5e94cf
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
elif [ "$(sha256sum "$GOLDEN" 2>/dev/null | cut -d' ' -f1)" != "$GOLDEN_HASH" ]; then
  echo "FAIL: /opt/golden/test_types.py has been modified (integrity mismatch)" >&2
  reward=0
else
  echo "ok: golden test bytes match the fix-commit extraction"
  run_pytest "golden test_func_param_type_uses_value_error_message" \
    /tmp/golden.out "$GOLDEN::test_func_param_type_uses_value_error_message" \
    || true
fi

# ---------- 2. the project's own entire existing test suite -------------------
echo "== the project's own existing test suite (tests/) =="
run_pytest "existing tests/ tree" /tmp/own.out tests || true

# ---------- 3. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  if ( cd "$SRC" && python3 -m pytest "$case" -c "$PTCFG" -q -p no:cacheprovider > "$out" 2>&1 ); then
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