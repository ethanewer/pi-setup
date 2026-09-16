#!/bin/bash
# Verifier for capstan-boom: an upstream-clone debugging task on semgrep/semgrep.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# scp-like git remotes (no protocol prefix, no trailing ".git") whose owner or
# repo name contains a dash are not converted into the https URL used to link
# report findings; get_url_from_sstp_url() returns the raw scp form. The
# verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, no history
#      was fetched, no tracked file was deleted, the only modified tracked
#      files are source files under cli/src/semgrep/ with at least one such
#      modification present, the semgrep_interfaces submodule is untouched,
#      the tree's own test files were not doctored, and `import semgrep`
#      resolves to the checked-out tree);
#   1. copies in and runs the project's own regression test for this bug,
#      extracted at image build time from the fix commit into /opt/golden/;
#   2. runs the project's own existing tests for this area from the tree,
#      proving the fix broke nothing else;
#   3. runs authored hidden cases over scp-like and protocol URL shapes the
#      upstream test does not use.
#
# Because the agent runs as root inside the trial container, section 0.5 also
# asserts the integrity of the harness's own inputs and of the interpreter
# startup path, so the verifier cannot be satisfied by writing a fake fix into
# site-packages (sitecustomize / .pth / interpreter files) or by editing
# /opt/golden. Those states are anchored on this script and on tests/manifest/,
# which live on the host and are mounted at /tests only after the agent phase.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=bb89271f8418167b9d4cee2668e3d38a36003978
FIX_SHA=483878b242d5217844af8b71068b60b495f34614
GOLDEN=/opt/golden/test_meta.py
GOLDEN_SHA=3420071f728036af43ba53a0409ccde6cd246b642c8ce5bb59046f9dad1b2754
MANIFEST_DIR=/tests/manifest
SP=/usr/local/lib/python3.12/site-packages
SUBMOD=cli/src/semgrep/semgrep_interfaces

export PYTHONDONTWRITEBYTECODE=1

run_pytest () {  # run_pytest LABEL OUT ...args  (cwd = $SRC/cli)
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC/cli" && python3 -m pytest "$@" -o addopts="" -q -p no:cacheprovider > "$out" 2>&1 ); then
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

# the semgrep_interfaces submodule must still be exactly the pinned gitlink
sub_gitlink=$(git -C "$SRC" ls-tree HEAD "$SUBMOD" 2>/dev/null | awk '{print $3}')
sub_head=$(git -C "$SRC/$SUBMOD" rev-parse HEAD 2>/dev/null || true)
if [ -n "$sub_gitlink" ] && [ "$sub_gitlink" = "$sub_head" ]; then
  echo "ok: submodule $SUBMOD is at the pinned gitlink"
else
  echo "FAIL: submodule $SUBMOD moved off its pinned gitlink" >&2
  reward=0
fi

saw_mod=0
bad_tree=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  # The agent works on the checked-out tree, so changes normally show as
  # unstaged (" M"). Some agent harnesses run `git add` as part of their
  # edit workflow, which turns the same change into a staged ("M  ") or
  # staged+unstaged ("MM") porcelain entry with the identical working-tree
  # content; a legitimate source fix must not be zeroed for that. Staged
  # changes to tests, to the submodule, deletions and additions are still
  # rejected, exactly as the unstaged ones are.
  case "$line" in
    " M $SUBMOD"*|" m $SUBMOD"*|"M  $SUBMOD"*|"MM $SUBMOD"*)
      echo "FAIL: submodule $SUBMOD was modified by the agent: $line" >&2; bad_tree=1 ;;
    " M cli/src/semgrep/"*|"M  cli/src/semgrep/"*|"MM cli/src/semgrep/"*)
      saw_mod=1
      ;;
    " M cli/tests/"*|" M tests/"*|"M  cli/tests/"*|"M  tests/"*|"MM cli/tests/"*|"MM tests/"*)
      echo "FAIL: tracked test file was modified by the agent: $line" >&2; bad_tree=1 ;;
    " M "*) # modified tracked file outside cli/src/semgrep/ and the project's tests
      echo "FAIL: a tracked file outside cli/src/semgrep/ was modified: $line" >&2; bad_tree=1 ;;
    " D "*) echo "FAIL: a tracked file was deleted: $line" >&2; bad_tree=1 ;;
    "?? "*) # untracked files: allowed outside the semgrep package and the submodule
      case "$line" in
        "?? cli/src/semgrep/"*)
          echo "FAIL: a new file was added inside the semgrep package: $line" >&2; bad_tree=1 ;;
        *) : ;;
      esac
      ;;
    *) echo "FAIL: unexpected working-tree change: $line" >&2; bad_tree=1 ;;
  esac
done <<< "$(git -C "$SRC" status --porcelain 2>/dev/null || true)"
if [ "$bad_tree" = 1 ]; then reward=0; else echo "ok: no unexpected working-tree changes"; fi
if [ "$saw_mod" = 0 ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2; reward=0
else
  echo "ok: at least one source file under cli/src/semgrep/ is modified"
fi

if ! ( cd / && python3 -c "import semgrep; import sys; sys.exit(0 if semgrep.__file__ == '$SRC/cli/src/semgrep/__init__.py' else 3)" >/dev/null 2>&1 ); then
  echo "FAIL: 'import semgrep' does not resolve to the checked-out tree at /app/src" >&2
  reward=0
else
  echo "ok: import semgrep resolves to $SRC/cli/src/semgrep/__init__.py"
fi

# ---------- 0.5. harness assets integrity ---------------------------------------
echo "== harness assets integrity =="

# a) nothing new at the top level of site-packages: a startup-injection patch
#    (sitecustomize.py, a new .pth, an added package dir, ...) shows up here.
new_entries=$(comm -13 <(sort "$MANIFEST_DIR/site-packages-root.lst") \
                          <(cd "$SP" && find . -maxdepth 1 -mindepth 1 -printf "%f\n" | sort))
if [ -n "$new_entries" ]; then
  echo "FAIL: unexpected new entries under $SP:" >&2
  echo "$new_entries" | sed 's/^/    /' >&2
  reward=0
else
  echo "ok: site-packages top level matches the bake-time set"
fi

# b) the two .pth files are byte-identical to bake time (the editable install
#    must still map `import semgrep` straight to the checked-out tree).
if (cd / && sha256sum -c "$MANIFEST_DIR/pth.sha256" > /dev/null 2>&1); then
  echo "ok: site-packages .pth files are the bake-time files"
else
  echo "FAIL: site-packages .pth files differ from bake time" >&2
  (cd / && sha256sum -c "$MANIFEST_DIR/pth.sha256" 2>&1 | grep -v ': OK$' | head -3 | sed 's/^/    /') >&2
  reward=0
fi

# c) the pinned test runner and the interpreter directory are unchanged (an
#    agent tampering with them would be trying to fake the test runs).
if (cd "$SP" && sha256sum -c "$MANIFEST_DIR/pytest.sha256" > /dev/null 2>&1); then
  echo "ok: pytest package files match the pinned install"
else
  echo "FAIL: pytest package files differ from the pinned install" >&2
  (cd "$SP" && sha256sum -c "$MANIFEST_DIR/pytest.sha256" 2>&1 | grep -v ': OK$' | head -3 | sed 's/^/    /') >&2
  reward=0
fi
if (cd /usr/local/bin && sha256sum -c "$MANIFEST_DIR/bin.sha256" > /dev/null 2>&1); then
  echo "ok: /usr/local/bin files match the base image"
else
  echo "FAIL: /usr/local/bin files differ from the base image" >&2
  (cd /usr/local/bin && sha256sum -c "$MANIFEST_DIR/bin.sha256" 2>&1 | grep -v ': OK$' | head -3 | sed 's/^/    /') >&2
  reward=0
fi

# d) the upstream regression test in /opt/golden is exactly the fix-commit bytes.
if [ "$(sha256sum "$GOLDEN" 2>/dev/null | awk '{print $1}')" = "$GOLDEN_SHA" ]; then
  echo "ok: /opt/golden/test_meta.py is the fix-commit file"
else
  echo "FAIL: /opt/golden/test_meta.py is missing or was tampered with" >&2
  reward=0
fi

# e) no untracked conftest.py anywhere in the tree (pytest would auto-load it).
bad_conftest=0
while IFS= read -r f; do
  if ! git -C "$SRC" ls-files --error-unmatch "${f#$SRC/}" > /dev/null 2>&1; then
    echo "FAIL: untracked pytest conftest file present: ${f#$SRC/}" >&2
    bad_conftest=1
  fi
done < <(find "$SRC" -name conftest.py -not -path '*/.git/*')
if [ "$bad_conftest" = 1 ]; then reward=0; fi

# ---------- 1. golden: the upstream regression test ---------------------------
echo "== golden test (upstream regression test for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
else
  cp "$GOLDEN" "$SRC/cli/tests/default/unit/test_meta.py"
  run_pytest "golden test_git_url_parser" /tmp/golden1.out \
    "tests/default/unit/test_meta.py::test_git_url_parser" || true
  run_pytest "golden test_get_url_from_sstp_url" /tmp/golden2.out \
    "tests/default/unit/test_meta.py::test_get_url_from_sstp_url" || true
fi

# ---------- 2. the project's own existing tests for this area ----------------
echo "== the project's own existing tests =="
run_pytest "existing e2e-pro test_meta.py::test_git_url_parser" /tmp/own1.out \
  "tests/default/e2e-pro/test_meta.py::test_git_url_parser" || true
run_pytest "existing unit test_clean_project_url.py" /tmp/own2.out \
  "tests/default/unit/test_clean_project_url.py" || true

# ---------- 3. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  if ( cd "$SRC/cli" && python3 -m pytest "$case" -o addopts="" -q -p no:cacheprovider > "$out" 2>&1 ); then
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