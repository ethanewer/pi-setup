#!/bin/bash
# Verifier for ballast-boom: an upstream-clone debugging task on PyCQA/flake8.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# on Python 3.12, the string-redaction step of the logical-line construction
# path miscounts escaped (doubled) curly braces inside f-strings, so the
# logical line handed to plugins is garbled and misaligned with the physical
# line. The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, no history
#      was fetched, no tracked file was deleted, the only modified tracked
#      files are source files under src/flake8/ with at least one such
#      modification present, the tree's own test file was not doctored, and
#      `import flake8` resolves to the checked-out tree);
#   1. copies in and runs the project's own regression test for this bug,
#      extracted at image build time from the fix commit into /opt/golden/;
#   2. runs the project's own existing test suite from the tree, proving the
#      fix broke nothing else;
#   3. runs three authored hidden-case files: two exercise the same redaction
#      code path from escaped-brace f-string inputs the upstream test does not
#      use (exact redacted output, plus a length-preservation property), and
#      one guards that non-f-string redaction is unaffected.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=2a811cc4d2aaed3e8eb5a9f04f08ccc8af7c0791
FIX_SHA=bdcd5c2c0afadaf7c92a4b26d96055cecdd38cf3
GOLDEN=/opt/golden/test_plugins.py

export PYTHONDONTWRITEBYTECODE=1

run_pytest () {  # run_pytest LABEL OUT ...args  (cwd = SRC)
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

ncommits=$(git -C "$SRC" rev-list --all --count 2>/dev/null || echo -)
if [ "$ncommits" != "1" ]; then
  echo "FAIL: the working clone contains $ncommits commits; it must contain exactly the pinned parent commit (history was fetched or added)" >&2
  reward=0
else
  echo "ok: exactly one commit object reachable in the working clone"
fi

saw_mod=0
bad_tree=0
# porcelain is "XY path" with X=staged, Y=worktree; an agent may legitimately
# `git add` its fix, so a modified file must count regardless of which column
# the M appears in (bare "M" on the left used to be rejected as "unexpected").
while IFS= read -r line; do
  [ -z "$line" ] && continue
  x=${line:0:1}; y=${line:1:1}; path=${line:3}
  case "$x$y" in
    \?\?)
      # untracked files are allowed only outside the flake8 package
      case "$path" in
        src/flake8/*)
          echo "FAIL: a new file was added inside the flake8 package: $path" >&2; bad_tree=1 ;;
        *) : ;;
      esac
      ;;
    *D*)
      echo "FAIL: a tracked file was deleted: $path" >&2; bad_tree=1
      ;;
    A*) # a newly added tracked file (staged add, possibly also modified)
      case "$path" in
        src/flake8/*)
          echo "FAIL: a new file was added inside the flake8 package: $path" >&2; bad_tree=1 ;;
        *)
          echo "FAIL: a new tracked file was added outside src/flake8/: $path" >&2; bad_tree=1 ;;
      esac
      ;;
    *M*) # modified (staged, worktree, or both), excluding delete/add cases above
      case "$path" in
        src/flake8/*)
          saw_mod=1
          ;;
        tests/*)
          echo "FAIL: tracked test file was modified by the agent: $path" >&2; bad_tree=1 ;;
        *)
          echo "FAIL: a tracked file outside src/flake8/ was modified: $path" >&2; bad_tree=1 ;;
      esac
      ;;
    *) echo "FAIL: unexpected working-tree change: $line" >&2; bad_tree=1 ;;
  esac
done <<< "$(git -C "$SRC" status --porcelain 2>/dev/null || true)"
if [ "$bad_tree" = 1 ]; then reward=0; else echo "ok: no unexpected working-tree changes"; fi
if [ "$saw_mod" = 0 ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2; reward=0
else
  echo "ok: at least one source file under src/flake8/ is modified"
fi

if ! ( cd / && python3 -c "import flake8; import sys; sys.exit(0 if flake8.__file__ == '$SRC/src/flake8/__init__.py' else 3)" >/dev/null 2>&1 ); then
  echo "FAIL: 'import flake8' does not resolve to the checked-out tree at /app/src" >&2
  reward=0
else
  echo "ok: import flake8 resolves to $SRC/src/flake8/__init__.py"
fi

# The fix must live in the source tree itself. Without this check, a wrapper
# that intercepts the call from outside the clone (a sitecustomize.py dropped
# into site-packages, a tree-root conftest.py, ...) can make every behavioural
# check pass while the checked-out processor.py still contains the buggy line.
shape=$(python3 - "$SRC/src/flake8/processor.py" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
if 'text = "x" * len(text)' in src:
    print("BUGGYLINE")
elif re.search(r"\.count\(['\"]\{['\"]\)", src) and re.search(r"\.count\(['\"]\}['\"]\)", src):
    print("OK")
else:
    print("NOBRACE")
PY
)
case "$shape" in
  OK) echo "ok: src/flake8/processor.py contains escaped-brace accounting in the source" ;;
  BUGGYLINE) echo "FAIL: the buggy FSTRING_MIDDLE redaction line is still present in src/flake8/processor.py" >&2; reward=0 ;;
  *) echo "FAIL: src/flake8/processor.py shows no escaped-brace accounting; the fix must be in the source tree, not in a wrapper" >&2; reward=0 ;;
esac

# ---------- 1. golden: the upstream regression test ---------------------------
echo "== golden test (upstream regression test for this bug) =="
GOLDEN_SHA=0d3181b38b4795bcf791a4463bd1897872a828e931548b1e1becbc16dce0ebc5
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
else
  # The golden file is baked into the image and the agent runs as root in the
  # same container, so it could retouch it to assert the buggy output. Pin its
  # content to the bytes extracted at build time from the fix commit.
  if [ "$(sha256sum "$GOLDEN" | cut -d' ' -f1)" != "$GOLDEN_SHA" ]; then
    echo "FAIL: /opt/golden/test_plugins.py was tampered with (sha256 mismatch)" >&2; reward=0
  else
    echo "ok: golden file integrity confirmed"
    cp "$GOLDEN" "$SRC/tests/integration/test_plugins.py"
    run_pytest "golden test_escaping_of_fstrings_in_string_redacter" /tmp/golden.out \
      --confcutdir="$SRC/tests" \
      "tests/integration/test_plugins.py::test_escaping_of_fstrings_in_string_redacter" || true
  fi
fi

# ---------- 2. the project's own existing test suite --------------------------
echo "== the project's own existing test suite =="
run_pytest "full project test suite" /tmp/own.out tests/ || true

# ---------- 3. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  # --confcutdir isolates the hidden-case runs from any conftest.py the agent
  # might have dropped into the tree as a runtime-interception wrapper.
  if ( cd "$SRC" && python3 -m pytest "$case" -o addopts="" -q -p no:cacheprovider \
        --confcutdir=/tests > "$out" 2>&1 ); then
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