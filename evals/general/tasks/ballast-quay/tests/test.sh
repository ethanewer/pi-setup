#!/bin/bash
# Verifier for ballast-quay: an upstream-clone debugging task on
# pylint-dev/pylint.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# the implicit-str-concat check (W1404) fires on an implicit concatenation of
# a raw string literal with a non-raw one (e.g. [r"\d" "\n"]). Such literals
# cannot be merged into a single literal, so the juxtaposition is deliberate
# and must not be reported; pylint reports it anyway because it never records
# whether a string token is raw. The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, no history
#      was fetched, no tracked file was deleted, the only modified tracked
#      files are linter source files under pylint/ with at least one such
#      modification present, and `import pylint` resolves to the checked-out
#      tree); no importable untracked file (.py/.pyc/.pth/.so/.pyd, startup
#      hooks, pytest config) may ship under /app/src, so a wrapper cannot
#      fake the fix from an untracked module;
#   0.5 asserts clean interpreter state: site-packages must still match the
#      build-time manifest (no planted sitecustomize/.pth shim), and the
#      harness-owned canaries (/opt/golden, /tests/hidden/*) must still be the
#      verified bytes (directory-listing hashes embedded below);
#   1. copies in and runs the project's own regression test for this bug,
#      extracted at image build time from the fix commit into /opt/golden/
#      (the fix-commit version of the implicit_str_concat functional test);
#   2. restores the tree's own version of that functional test and runs it
#      again (the pre-existing expectations must stay green), and runs the
#      project's own unit tests for the string checker module;
#   3. runs three authored hidden-case files: raw-prefix shapes the upstream
#      test does not use, plain-concatenation guards (the check must not be
#      disabled), and multi-literal chains.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=2ef1766c3923ee7753cea771959227a35e74972c
FIX_SHA=16faa29d6bc6ba6533efe426038da62a81ca272b
GOLDEN_DIR=tests/functional/i/implicit

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

# ---------- 0. tree provenance -------------------------------------------------
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
while IFS= read -r line; do
  [ -z "$line" ] && continue
  case "$line" in
    " M pylint/"*)
      saw_mod=1
      ;;
    " M "*)
      echo "FAIL: a tracked file outside pylint/ was modified: $line" >&2; bad_tree=1 ;;
    " D "*) echo "FAIL: a tracked file was deleted: $line" >&2; bad_tree=1 ;;
    "?? "*) # untracked files are allowed only outside the pylint package, and
      # only if they cannot hook a Python interpreter: importable files
      # (.py/.pyc/.pth/.so/.pyd) and pytest startup config would let a wrapper
      # intercept the check (e.g. /app/src/sitecustomize.py plus a cosmetic
      # tracked edit) while the real bug stays in the tracked source.
      case "$line" in
        "?? pylint/"*)
          echo "FAIL: a new file was added inside the pylint package: $line" >&2; bad_tree=1 ;;
        *)
          case "$line" in
            *".py"|*".pyc"|*".pth"|*".so"|*".pyd"|*"pytest.ini")
              echo "FAIL: an importable untracked file would ship with /app/src: $line" >&2; bad_tree=1 ;;
            *) : ;;
          esac
          ;;
      esac
      ;;
    *) echo "FAIL: unexpected working-tree change: $line" >&2; bad_tree=1 ;;
  esac
done <<< "$(git -C "$SRC" status --porcelain 2>/dev/null || true)"
if [ "$bad_tree" = 1 ]; then reward=0; else echo "ok: no unexpected working-tree changes"; fi
# A tracked file whose assume-unchanged ('h') or skip-worktree ('S') bit is
# set is INVISIBLE to `git status --porcelain`, so a tampered test or
# configuration file could otherwise be smuggled past the checks above while
# the real bug stays in the tracked source. Healthy index entries report 'H'
# even for normally-modified files, so anything else is a red flag.
hidden_flags="$(git -C "$SRC" ls-files -v 2>/dev/null | awk '$1 != "H" {print $1" "$2}' | head -20)"
if [ -n "$hidden_flags" ]; then
  echo "FAIL: non-H index flag on tracked file(s) (assume-unchanged/skip-worktree hides changes from git status): $(echo "$hidden_flags" | tr '\n' '; ')" >&2
  reward=0
else
  echo "ok: no assume-unchanged / skip-worktree index flags"
fi
if [ "$saw_mod" = 0 ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2; reward=0
else
  echo "ok: at least one source file under pylint/ is modified"
fi

if ! ( cd / && python3 -c "import pylint; import sys; sys.exit(0 if pylint.__file__ == '$SRC/pylint/__init__.py' else 3)" >/dev/null 2>&1 ); then
  echo "FAIL: 'import pylint' does not resolve to the checked-out tree at /app/src" >&2
  reward=0
else
  echo "ok: import pylint resolves to $SRC/pylint/__init__.py"
fi

# ---------- 0.5 interpreter-state and canary integrity ---------------------
# A wrapper need not touch the git tree at all: a planted sitecustomize/.pth
# in site-packages, or an untracked startup hook in /app/src, would be imported
# by every interpreter the verifier starts. The build-time site-packages
# manifest and the embedded canaries (hashes of the harness-owned files) make
# any such drift fatal.
echo "== interpreter-state and canary integrity =="

if [ ! -s /opt/site_packages_manifest.txt ]; then
  echo "FAIL: /opt/site_packages_manifest.txt missing (image not built from the current Dockerfile)" >&2
  reward=0
elif ! python3 - <<'PY' >/tmp/site_manifest.out 2>&1
import hashlib, pathlib, site
root = pathlib.Path(site.getsitepackages()[0])
lines = []
for p in sorted(root.rglob("*"), key=str):
    if p.is_file() and "__pycache__" not in p.parts:
        lines.append(hashlib.sha256(p.read_bytes()).hexdigest() + "  " + str(p.relative_to(root)))
current = "\n".join(lines) + "\n"
expected = pathlib.Path("/opt/site_packages_manifest.txt").read_text()
raise SystemExit(0 if current == expected else 1)
PY
then
  echo "FAIL: site-packages differs from the build-time manifest (planted interpreter hook or installed change)" >&2
  reward=0
else
  echo "ok: site-packages matches the build-time manifest"
fi

check_canary () {  # check_canary DIR EXPECTED_SHA
  dir="$1"; expected="$2"
  actual="$(cd "$dir" 2>/dev/null && find . -type f ! -path '*/__pycache__/*' -print0 2>/dev/null \
    | LC_ALL=C sort -z \
    | while IFS= read -r -d "" f; do printf '%s  %s\n' "$(sha256sum "$f" | awk '{print $1}')" "${f#./}"; done)"
  now="$(printf '%s\n' "$actual" | sha256sum | awk '{print $1}')"
  if [ "$now" = "$expected" ]; then
    echo "ok: canary $dir unchanged"
    return 0
  fi
  echo "FAIL: canary $dir changed from its verified content" >&2
  reward=0
  return 1
}

check_canary /opt/golden 67e69d51c8fa9190cdd2a7962d93ad58ea1d1ce496683e1c86f3169014736317
check_canary /tests/hidden/case-guards 76cd0de2b739e2adcf038084746230f52eb7b7c2c9c927648f6dcd3935dc9338
check_canary /tests/hidden/case-raw-prefixes dc7a9aa7bef46d6a619c6335175d93564734de587d0c8acfa8537ef21583467c
check_canary /tests/hidden/case-chains 2d273d8d164653de1632f8be74711bc80693ee323286dab277f19a0bf6457111

# ---------- 1. golden: the upstream regression test -----------------------------
echo "== golden test (upstream regression test for this bug) =="
if [ ! -s /opt/golden/implicit_str_concat.py ] || [ ! -s /opt/golden/implicit_str_concat.txt ]; then
  echo "FAIL: golden test files missing from the image" >&2; reward=0
else
  cp /opt/golden/implicit_str_concat.py "$SRC/$GOLDEN_DIR/implicit_str_concat.py"
  cp /opt/golden/implicit_str_concat.txt "$SRC/$GOLDEN_DIR/implicit_str_concat.txt"
  run_pytest "golden implicit_str_concat functional test" /tmp/golden.out \
    tests/test_functional.py -k implicit_str_concat || true
fi

# ---------- 2. the project's own existing tests ----------------------------------
echo "== the project's own existing tests =="
# Restore the tree's own version of the functional test from git (the
# parent-commit bytes), then run it: the pre-existing expectations must stay
# green with the fix applied.
( cd "$SRC" && git checkout -q -- "$GOLDEN_DIR/implicit_str_concat.py" "$GOLDEN_DIR/implicit_str_concat.txt" )
run_pytest "tree's own implicit_str_concat functional test" /tmp/own_func.out \
  tests/test_functional.py -k implicit_str_concat || true
run_pytest "project's own string checker unit tests" /tmp/own_unit.out \
  tests/checkers/unittest_strings.py || true

# ---------- 3. hidden cases -------------------------------------------------------
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