#!/bin/bash
# Verifier for companion-berm: an upstream-clone debugging task on
# python-poetry/poetry.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# the resolver's Indicator.context() only clears the class-level
# Indicator.CONTEXT on the happy path, so the current activity label leaks when
# the body of the with-block raises. The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, no history
#      was fetched, no tracked file was deleted, the only modified tracked
#      files are source files under src/poetry/ with at least one such
#      modification present, no tracked test file was changed, and
#      poetry.puzzle.provider resolves to the checked-out tree); no importable
#      untracked file (.py/.pyc/.pth/.so/.pyd, startup hooks, pytest config)
#      may ship under /app/src, so a wrapper cannot fake the fix from an
#      untracked module;
#   0.5 asserts clean interpreter state: site-packages must still match the
#      build-time manifest (no planted sitecustomize/.pth shim), and the
#      harness-owned canaries (/opt/golden, /tests/hidden/*) must still be the
#      verified bytes (directory-listing hashes embedded below);
#   1. runs the agent's own reproduction at /app/reproduce_indicator_leak.py
#      against a clean PRE-FIX (buggy) tree and requires it to FAIL, proving
#      the reproduction genuinely detects the leak and does not just exit 0;
#   2. runs the same reproduction against the REPAIRED tree and requires it to
#      PASS;
#   3. copies in and runs the project's own regression test for this bug,
#      extracted at image build time from the fix commit into /opt/golden/;
#   4. runs a fast, offline slice of the project's own existing unresolved
#      resolver tests to prove the fix broke nothing else (one unrelated test,
#      test_complete_package_merges_same_source_and_no_source, fails on this
#      poetry-core revision even before the fix, so it is excluded);
#   5. runs three authored hidden-case files over other exception types, the
#      normal-exit and re-entry paths, and the indicator's label formatter -
#      inputs the upstream test does not use.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=35eb5025dc7374db74ef26ce32a0e70f54d2e3b6
FIX_SHA=b8383e3cda4e7336eb9048b1e7388b5b914a4653
PY=/opt/poetry-venv/bin/python
PROVIDER_SRC="$SRC/src/poetry/puzzle/provider.py"

export PYTHONDONTWRITEBYTECODE=1

run_pytest () {  # run_pytest LABEL OUT ...args  (cwd = SRC)
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC" && "$PY" -m pytest "$@" -o addopts="" -q -p no:randomly > "$out" 2>&1 ); then
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
mod_test=0
bad_tree=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  case "$line" in
    " M src/poetry/"*)
      saw_mod=1
      ;;
    " M tests/"*)
      echo "FAIL: a tracked test file was modified: $line" >&2; mod_test=1 ;;
    " M "*)
      echo "FAIL: a tracked file outside src/poetry/ was modified: $line" >&2; bad_tree=1 ;;
    " D "*) echo "FAIL: a tracked file was deleted: $line" >&2; bad_tree=1 ;;
    "?? "*) # untracked files are allowed only outside the poetry package, and
      # only if they cannot hook a Python interpreter: importable files
      # (.py/.pyc/.pth/.so/.pyd) and pytest startup config would let a wrapper
      # intercept the indicator (e.g. /app/src/sitecustomize.py plus a cosmetic
      # tracked edit) while the real bug stays in the tracked source.
      case "$line" in
        "?? src/poetry/"*)
          echo "FAIL: a new file was added inside the poetry package: $line" >&2; bad_tree=1 ;;
        *)
          case "$line" in
            *".py"|*".pyc"|*".pth"|*".so"|*".pyd"|*"pytest.ini")
              echo "FAIL: an importable untracked file would ship in the tree: $line" >&2; bad_tree=1 ;;
            *) : ;;
          esac
          ;;
      esac
      ;;
    *) echo "FAIL: unexpected working-tree change: $line" >&2; bad_tree=1 ;;
  esac
done <<< "$(git -C "$SRC" status --porcelain 2>/dev/null || true)"
if [ "$mod_test" = 1 ]; then reward=0; fi
if [ "$bad_tree" = 1 ]; then reward=0; else echo "ok: no unexpected working-tree changes"; fi
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
  echo "ok: at least one source file under src/poetry/ is modified"
fi

if ! ( cd / && "$PY" -c "import poetry.puzzle.provider as m; import sys; sys.exit(0 if m.__file__.startswith('$SRC/src/poetry/') else 3)" >/dev/null 2>&1 ); then
  echo "FAIL: 'poetry.puzzle.provider' does not resolve to the checked-out tree at /app/src" >&2
  reward=0
else
  echo "ok: poetry.puzzle.provider resolves to $SRC/src/poetry/"
fi

# ---------- 0.5 interpreter-state and canary integrity ---------------------
echo "== interpreter-state and canary integrity =="
if [ ! -s /opt/site_packages_manifest.txt ]; then
  echo "FAIL: /opt/site_packages_manifest.txt missing (image not built from the current Dockerfile)" >&2
  reward=0
elif ! "$PY" - <<'PY' >/tmp/site_manifest.out 2>&1
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
  actual="$(cd "$dir" 2>/dev/null && find . -type f \
    ! -path '*/__pycache__/*' ! -path '*/.pytest_cache/*' -print0 2>/dev/null \
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

check_canary /opt/golden b97f04605d7ab4e95bb1529df4f7b5de0d1cb95ef50349d79ae7f773025d6a77
check_canary /tests/hidden/case-exception-types 8fd8051b5bb0212dba45df9ff405f2964340f6c561fbaab44bacf9c2c68138ea
check_canary /tests/hidden/case-normal-reentry 0bc4dcbad47e9b659d5d12eaee988a5635c4aca944b4315ac2f41563c3db66d2
check_canary /tests/hidden/case-formatter a12237810e1451636a4669b6f951d9be1211c8cd4a82c206ec647fd75659bba9

# ---------- 1. reproduction against the PRE-FIX (buggy) tree ----------------
echo "== reproduction must FAIL on a clean pre-fix tree =="
if [ ! -f /app/reproduce_indicator_leak.py ]; then
  echo "FAIL: deliverable /app/reproduce_indicator_leak.py is missing" >&2; reward=0
else
  # temporarily restore the parent (buggy) provider, run the reproduction, then
  # restore whatever the agent changed. This proves the reproduction genuinely
  # detects the leak rather than always exiting 0.
  cp "$PROVIDER_SRC" /tmp/agent_provider.py
  git -C "$SRC" checkout -q -- src/poetry/puzzle/provider.py
  set +e
  ( cd /app && "$PY" reproduce_indicator_leak.py ) >/tmp/repro_buggy.out 2>&1
  rc_pre=$?
  cp /tmp/agent_provider.py "$PROVIDER_SRC"
  set -e
  if [ "$rc_pre" -eq 0 ]; then
    echo "FAIL: reproduction exited 0 on the buggy pre-fix tree; it does not detect the bug" >&2
    cat /tmp/repro_buggy.out | sed 's/^/    /' >&2
    reward=0
  else
    echo "ok: reproduction correctly fails on the buggy pre-fix tree (exit $rc_pre)"
  fi
fi

# ---------- 2. reproduction against the REPAIRED tree -----------------------
echo "== reproduction must PASS on the repaired tree =="
if [ ! -f /app/reproduce_indicator_leak.py ]; then
  : # already reported missing above
elif ( cd /app && "$PY" reproduce_indicator_leak.py ) >/tmp/repro_fixed.out 2>&1; then
  echo "ok: reproduction passes on the repaired tree"
else
  echo "FAIL: reproduction failed on the repaired tree" >&2
  tail -40 /tmp/repro_fixed.out | sed 's/^/    /' >&2
  reward=0
fi

# ---------- 3. golden: the upstream regression test ---------------------------
echo "== golden test (upstream regression test for this bug) =="
if [ ! -s /opt/golden/test_indicator_context_resets_on_exception.py ]; then
  echo "FAIL: golden test file missing from the image" >&2; reward=0
else
  # run from a copy so pytest's cache never touches the harness-owned /opt/golden
  rm -rf /tmp/golden_run && mkdir -p /tmp/golden_run
  cp /opt/golden/test_indicator_context_resets_on_exception.py /tmp/golden_run/
  run_pytest "golden test_indicator_context_resets_on_exception" /tmp/golden.out \
    /tmp/golden_run/test_indicator_context_resets_on_exception.py || true
fi

# ---------- 4. the project's own existing tests -------------------------------
echo "== project's own existing resolver tests =="
# Fast, offline slice of the project's own puzzle provider tests. One unrelated
# test fails on this poetry-core revision even before the fix (a version-string
# formatting assertion), so it is excluded; the remainder must stay green.
run_pytest "project's own tests/puzzle/test_provider.py" /tmp/own.out \
  tests/puzzle/test_provider.py -k "not test_complete_package_merges_same_source_and_no_source" || true

# ---------- 5. hidden cases ------------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  if ( cd "$SRC" && "$PY" -m pytest "$case" -o addopts="" -q -p no:randomly > "$out" 2>&1 ); then
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
