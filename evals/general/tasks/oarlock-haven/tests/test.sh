#!/bin/bash
# Verifier for oarlock-haven: an upstream-clone debugging task on
# pytest-dev/pytest.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# failed monkeypatch mutations (setitem/delitem on an immutable mapping or a
# mapping subclass that refuses an operation, delattr of an attribute that
# cannot be removed) leave a stale rollback entry, so a later
# monkeypatch.undo() re-raises the original exception instead of being a
# harmless no-op. The verifier:
#   0. asserts tree provenance (HEAD still the pinned parent commit, the
#      upstream fix commit unreachable from the working clone, exactly one
#      commit in the object store, no tracked file deleted, only source files
#      under src/_pytest/ modified with at least one such modification, no new
#      or untracked files added inside the repository, nothing under testing/
#      or elsewhere touched, `import _pytest.monkeypatch` resolving to the
#      checked-out tree, no sitecustomize.py wrapper on the interpreter path,
#      and the undo-append line after the mutation in the checked-out source);
#   1. runs the agent's own reproduction script (/app/repro_failed_undo.py)
#      against the pristine pre-fix tree (must FAIL) and against the agent's
#      repaired tree (must PASS);
#   2. copies in and runs the project's own regression test for this bug,
#      extracted at image build time from the fix commit into /opt/golden/
#      (sha256-pinned) — also proving it fails on the pristine tree;
#   3. runs the project's own existing test battery from the tree (the
#      monkeypatch module, the pytester module, and fixtures+recwarn),
#      proving the fix broke nothing else;
#   4. runs three authored hidden-case files: failure shapes and rollback
#      orderings the upstream regression test does not use, all of which must
#      fail on the pristine tree and pass on the repaired tree.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=efa117ad49ce197c5971b12310d53b73ed678d92
FIX_SHA=a88e91bacaa98b68fe80e07a138ce40994bd8797
GOLDEN=/opt/golden/test_monkeypatch.py
GOLDEN_SHA=c683f99dddb16fb51bad90284c14cf4ccc50fd4e8ad0c8cb94f238af191aeced
MP_FILE="$SRC/src/_pytest/monkeypatch.py"
REPRO=/app/repro_failed_undo.py

export PYTHONDONTWRITEBYTECODE=1

fail () { echo "FAIL: $*" >&2; reward=0; }
ok ()   { echo "ok: $*"; }

run_pytest () {  # run_pytest LABEL OUT ...args  (cwd = SRC, tree addopts apply)
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC" && python3 -m pytest "$@" -q -p no:cacheprovider > "$out" 2>&1 ); then
    ok "$label"
    return 0
  fi
  echo "FAIL: $label" >&2
  tail -40 "$out" | sed 's/^/    /' >&2
  reward=0
  return 1
}

expect_fail_pytest () {  # expect_fail_pytest LABEL OUT ...args: run must FAIL
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC" && python3 -m pytest "$@" -q -p no:cacheprovider > "$out" 2>&1 ); then
    fail "$label (expected it to fail)"
    return 1
  fi
  ok "$label"
  return 0
}

restore_pristine_mp () {  # put the pre-fix monkeypatch.py back on disk
  git -C "$SRC" show "HEAD:src/_pytest/monkeypatch.py" > "$MP_FILE.tmp" \
    && mv -f "$MP_FILE.tmp" "$MP_FILE"
}

# ---------- 0. tree provenance -----------------------------------------------
echo "== tree provenance =="
if [ ! -d "$SRC/.git" ]; then
  fail "/app/src is not a git clone"
elif [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  fail "/app/src HEAD is not the pinned parent commit"
else
  ok "HEAD is $PARENT_SHA"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  fail "the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)"
else
  ok "fix commit not present in the working clone"
fi

ncommits=$(git -C "$SRC" rev-list --all --count 2>/dev/null || echo -)
if [ "$ncommits" != "1" ]; then
  fail "the working clone contains $ncommits commits; it must contain exactly the pinned parent commit (history was fetched or added)"
else
  ok "exactly one commit object reachable in the working clone"
fi

# `git status --porcelain` is silent about tracked files marked
# assume-unchanged (lowercase tag, e.g. 'h') or skip-worktree ('S'): the index
# flag hides their working-tree modifications. Earlier waves caught a verifier
# that skipped every test this way, so any such flag is a hard provenance fail.
if git -C "$SRC" ls-files -v | grep -E "^[a-zS]" >/dev/null 2>&1; then
  fail "a tracked file is marked assume-unchanged/skip-worktree, hiding its working-tree state from git status:"
  git -C "$SRC" ls-files -v | grep -E "^[a-zS]" | sed 's/^/    /' >&2
else
  ok "no tracked file hides worktree state via assume-unchanged/skip-worktree flags"
fi

saw_mod=0
bad_tree=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  x=${line:0:1}; y=${line:1:1}; path=${line:3}
  case "$x$y" in
    \?\?)
      fail "a new (untracked) file was added inside the repository: $path"
      bad_tree=1
      ;;
    *D*)
      fail "a tracked file was deleted: $path"
      bad_tree=1
      ;;
    A*)
      fail "a new tracked file was added: $path"
      bad_tree=1
      ;;
    *M*) # modified (staged, worktree, or both), excluding delete/add above
      case "$path" in
        src/_pytest/*)
          saw_mod=1
          ;;
        *)
          fail "a tracked file outside src/_pytest/ was modified: $path"
          bad_tree=1
          ;;
      esac
      ;;
    *) fail "unexpected working-tree change: $line"; bad_tree=1 ;;
  esac
done <<< "$(git -C "$SRC" status --porcelain 2>/dev/null || true)"
if [ "$bad_tree" = 0 ]; then ok "no unexpected working-tree changes"; fi
if [ "$saw_mod" = 0 ]; then
  fail "the deliverable /app/src is unchanged (no fix was implemented)"
else
  ok "at least one source file under src/_pytest/ is modified"
fi

if ! ( cd / && python3 -c "import _pytest.monkeypatch as m; import sys; sys.exit(0 if m.__file__ == '$MP_FILE' else 3)" >/dev/null 2>&1 ); then
  fail "'import _pytest.monkeypatch' does not resolve to the checked-out tree at $SRC"
else
  ok "import _pytest.monkeypatch resolves to $MP_FILE"
fi

if python3 -c "import sitecustomize" >/dev/null 2>&1; then
  fail "a sitecustomize module is importable on the interpreter path (out-of-tree wrapper); the fix must be inside the source tree"
else
  ok "no sitecustomize wrapper on the interpreter path"
fi

# The fix must live in the checked-out source itself: the undo-append line must
# come AFTER the mutation line in each of the three affected methods. Without
# this check, an interception wrapper could make every behavioural check pass
# while the checked-out file still contains the buggy ordering.
shape=$(python3 - "$MP_FILE" <<'PY'
import sys
src = open(sys.argv[1]).read()
problems = []

def body_of(name):
    i = src.find("    def " + name + "(")
    if i == -1:
        problems.append("method %s not found" % name)
        return ""
    j = src.find("\n    def ", i + 8)
    return src[i:j if j != -1 else len(src)]

def check(fn_name, append_needle, mutation_needles):
    body = body_of(fn_name)
    if not body:
        return
    ai = body.rfind(append_needle)
    mi = -1
    for n in mutation_needles:
        mi = max(mi, body.rfind(n))
    if ai == -1:
        problems.append("%s: undo-append line not found" % fn_name)
    elif mi == -1:
        problems.append("%s: mutation line not found" % fn_name)
    elif ai < mi:
        problems.append(
            "%s: undo entry is recorded BEFORE the mutation; it must only be "
            "recorded after the mutation succeeds" % fn_name
        )

check("setitem", "self._setitem.append", ["dic[name] = value"])
check("delitem", "self._setitem.append", ["del dic[name]"])
check("delattr", "self._setattr.append", ["delattr(target, name)"])
print("\n".join(problems))
sys.exit(1 if problems else 0)
PY
)
if [ -z "$shape" ]; then
  ok "source ordering: undo entries are recorded after each mutation"
else
  echo "FAIL: the fix must live in the checked-out source, but the ordering is wrong" >&2
  echo "$shape" | sed 's/^/    /' >&2
  reward=0
fi

# ---------- 1. reproduction deliverable ---------------------------------------
echo "== reproduction deliverable =="
if [ ! -s "$REPRO" ]; then
  fail "deliverable /app/repro_failed_undo.py is missing or empty"
else
  # against the agent's repaired tree, the reproduction must PASS
  if python3 "$REPRO" > /tmp/repro-agent.out 2>&1; then
    ok "reproduction passes against the repaired tree"
  else
    echo "FAIL: reproduction /app/repro_failed_undo.py failed against the repaired tree" >&2
    tail -40 /tmp/repro-agent.out | sed 's/^/    /' >&2
    reward=0
  fi
  # against the pristine pre-fix tree, the reproduction must FAIL
  cp "$MP_FILE" /tmp/agent_mp.py
  if restore_pristine_mp && python3 "$REPRO" > /tmp/repro-pristine.out 2>&1; then
    fail "reproduction PASSED against the pristine pre-fix tree (it does not exercise the bug, or the tree was not really fixed in source)"
  else
    ok "reproduction fails against the pristine pre-fix tree"
  fi
  cp /tmp/agent_mp.py "$MP_FILE"
fi

# ---------- 2..3. project's own regression test + own test battery ------------
echo "== the project's own existing test battery =="
# Run FIRST, before any golden copy touches testing/: these must run the
# parent-commit versions from the working tree, with the tree's own addopts
# (-p pytester).
run_pytest "own battery: testing/test_monkeypatch.py" /tmp/own1.out testing/test_monkeypatch.py || true
run_pytest "own battery: testing/test_pytester.py" /tmp/own2.out testing/test_pytester.py || true
run_pytest "own battery: testing/test_tmpdir.py + testing/test_pathlib.py + testing/test_recwarn.py" /tmp/own3.out \
  testing/test_tmpdir.py testing/test_pathlib.py testing/test_recwarn.py || true

echo "== golden regression test (upstream test for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  fail "golden regression test missing from image"
elif [ "$(sha256sum "$GOLDEN" | cut -d' ' -f1)" != "$GOLDEN_SHA" ]; then
  fail "/opt/golden/test_monkeypatch.py was tampered with (sha256 mismatch)"
else
  ok "golden file integrity confirmed (sha256 pinned)"
  # prove the golden test really bites: it must FAIL on the pristine tree
  cp "$MP_FILE" /tmp/agent_mp.py
  restore_pristine_mp
  cp "$GOLDEN" "$SRC/testing/test_monkeypatch.py"
  expect_fail_pytest "golden regression test fails against the pristine pre-fix tree" /tmp/golden-pristine.out \
    "testing/test_monkeypatch.py::test_failed_delattr" \
    "testing/test_monkeypatch.py::test_failed_setitem" \
    "testing/test_monkeypatch.py::test_failed_delitem" || true
  cp /tmp/agent_mp.py "$MP_FILE"
  # now run it on the agent's repaired tree
  cp "$GOLDEN" "$SRC/testing/test_monkeypatch.py"
  run_pytest "golden regression test (full fix-version file) passes on the repaired tree" /tmp/golden.out \
    testing/test_monkeypatch.py || true
  run_pytest "golden regression test nodeids pass on the repaired tree" /tmp/golden2.out \
    "testing/test_monkeypatch.py::test_failed_delattr" \
    "testing/test_monkeypatch.py::test_failed_setitem" \
    "testing/test_monkeypatch.py::test_failed_delitem" \
    "testing/test_monkeypatch.py::test_setitem_delitem_oldval_captured_before_mutation" || true
  # restore the parent-commit testing/test_monkeypatch.py those runs overwrote,
  # so the working tree still differs only under src/_pytest/ after the verdict
  git -C "$SRC" show HEAD:testing/test_monkeypatch.py > "$SRC/testing/test_monkeypatch.py.tmp" \
    && mv -f "$SRC/testing/test_monkeypatch.py.tmp" "$SRC/testing/test_monkeypatch.py"
fi

# ---------- 4. hidden cases ---------------------------------------------------
# The hidden-case files are also sha256-pinned: the agent shares /tests with the
# verifier, so doctored copies must be rejected rather than trusted.
HIDDEN_CASE_SHA='
case-guarded-mapping/test_guarded_mapping.py 5cc41ca81a055b68f30b4a65a986bdce14390ee950557419fe0a917449ea23a7
case-mixed-outcome/test_mixed_outcome.py 838981fc956706abb9dbde5d6a23c1c5bfb6e002ed42e52c139dfc18fd6b91a6
case-readonly-property/test_readonly_property.py a9cdf0301797f7362fa2bfda9ccab491886f059ade6c53ed181eefb3264611c7'
echo "== hidden cases =="
n_hidden=0
pristine_passes=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  case_file=$(find "$case" -maxdepth 1 -name 'test_*.py' | head -1)
  rel=${name}/$(basename "$case_file")
  want=$(printf '%s' "$HIDDEN_CASE_SHA" | awk -v r="$rel" '$1==r {print $2}')
  if [ -z "$want" ] || [ "$(sha256sum "$case_file" | cut -d' ' -f1)" != "$want" ]; then
    fail "hidden case $rel was tampered with (sha256 mismatch)"
    continue
  fi
  out="/tmp/hidden-${name}.out"
  if ( cd "$SRC" && python3 -m pytest "$case" -q -p no:cacheprovider --confcutdir=/tests > "$out" 2>&1 ); then
    ok "hidden case $name passes on the repaired tree"
  else
    echo "FAIL: hidden case $name" >&2
    tail -40 "$out" | sed 's/^/    /' >&2
    reward=0
  fi
  # every hidden case must genuinely exercise the bug: fail on the pristine tree
  cp "$MP_FILE" /tmp/agent_mp.py
  restore_pristine_mp
  if ( cd "$SRC" && python3 -m pytest "$case" -q -p no:cacheprovider --confcutdir=/tests > /tmp/hidden-pristine.out 2>&1 ); then
    fail "hidden case $name PASSED against the pristine pre-fix tree (the case does not exercise the bug)"
    pristine_passes=$((pristine_passes + 1))
  else
    ok "hidden case $name fails against the pristine pre-fix tree"
  fi
  cp /tmp/agent_mp.py "$MP_FILE"
done
if [ "$n_hidden" -lt 2 ]; then
  fail "fewer than two hidden cases exist"
else
  ok "$n_hidden hidden cases exercised"
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0