#!/bin/bash
# Verifier for caulk-ebb: an upstream-clone debugging task on
# networkx/networkx.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug
# (issue #8726): geometric_soft_configuration_graph computes the mean hidden
# degree from a kappas MAPPING by summing the mapping's KEYS
# ('sum(kappas) / len(kappas)') instead of its values, so string node labels
# raise TypeError and integer labels silently act as the degrees.  The verifier:
#   0. checks the deliverables exist and that /app/reproduce_failure.py truly
#      exercises the generator;
#   0.5 asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not present in the working clone, no history was
#      fetched, nothing deleted, the only tracked modification is
#      networkx/generators/geometric.py and at least one is present, no
#      untracked importable files, no interpreter-hook shims anywhere, and
#      `import networkx` resolves to the checked-out tree);
#   1. runs the agent's own reproduction against a pristine copy of the
#      generator (it must FAIL, proving it is a genuine reproduction) and
#      against the agent's fixed tree (it must PASS);
#   2. copies in and runs the project's own regression test for this bug,
#      extracted at image build time from the fix commit into /opt/golden/
#      (the fix-commit version of networkx/generators/tests/test_geometric.py,
#      all 55 tests);
#   3. restores the tree's own version of that module and runs it again (the
#      54 pre-existing tests must stay green);
#   4. runs two authored hidden-case files over mapping shapes the upstream
#      test does not use (string labels; integer labels unrelated to the
#      degrees with an exact radial-layout match).
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=195092869192b762fa553ef3a9ca5758e1d83ee3
FIX_SHA=e9eac8a7e04df0b9cdcff8ed1682b3971678f4ed
REPRO=/app/reproduce_failure.py

# Neutralise every interpreter-hook / import-redirection vector before each
# python invocation: a planted sitecustomize.py or .pth in /app, user-site
# packages (pip install --user could shadow the editable install) or PYTHON*
# environment variables must not influence any run below.
export -n PYTHONPATH PYTHONSTARTUP PYTHONHOME 2>/dev/null || true
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1

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

# ---------- 0. deliverables ----------------------------------------------------
echo "== deliverables =="
if [ ! -s "$REPRO" ]; then
  echo "FAIL: deliverable $REPRO is missing or empty" >&2; reward=0
elif ! grep -q "geometric_soft_configuration_graph" "$REPRO" 2>/dev/null; then
  echo "FAIL: deliverable $REPRO does not exercise geometric_soft_configuration_graph" >&2
  reward=0
else
  echo "ok: $REPRO present and exercises the generator"
fi
if [ ! -d "$SRC/.git" ]; then
  echo "FAIL: /app/src is not a git clone" >&2; reward=0
fi

# ---------- 0.5 tree provenance -------------------------------------------------
echo "== tree provenance =="
if [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  echo "FAIL: /app/src HEAD is not the pinned parent commit" >&2; reward=0
else
  echo "ok: HEAD is $PARENT_SHA"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  echo "FAIL: the upstream fix commit is present in the working clone (the answer was fetched, not implemented)" >&2
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
    " M networkx/generators/geometric.py")
      saw_mod=1
      ;;
    " M "*)
      echo "FAIL: a tracked file outside networkx/generators/geometric.py was modified: $line" >&2; bad_tree=1 ;;
    " D "*) echo "FAIL: a tracked file was deleted: $line" >&2; bad_tree=1 ;;
    "?? "*/__pycache__/|"?? .pytest_cache/")
      : ;;  # harmless build byproducts of the agent's own pytest runs
    "?? "*)
      # Untracked files are red flags when importable (.py/.pyc/.pth/.so/
      # .pyd, e.g. a sitecustomize.py that wins on sys.path from cwd) or when
      # they touch tracked paths.  Everything untracked is rejected here for
      # simplicity; instruct agents to keep scratch files out of the repo.
      echo "FAIL: untracked file inside the repository: $line" >&2; bad_tree=1 ;;
    *) echo "FAIL: unexpected working-tree change: $line" >&2; bad_tree=1 ;;
  esac
done <<< "$(git -C "$SRC" status --porcelain 2>/dev/null || true)"
if [ "$bad_tree" = 1 ]; then reward=0; else echo "ok: no unexpected working-tree changes"; fi
# A tracked file whose assume-unchanged ('h') or skip-worktree ('S') bit is
# set is INVISIBLE to `git status --porcelain`; healthy index entries report
# 'H', so anything else is a smuggling red flag.
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
  echo "ok: at least one modification in networkx/generators/geometric.py"
fi

if ! ( cd / && python3 -c "import networkx; import sys; sys.exit(0 if networkx.__file__.startswith('$SRC/networkx/__init__.py') else 3)" >/dev/null 2>&1 ); then
  echo "FAIL: 'import networkx' does not resolve to the checked-out tree at /app/src" >&2
  reward=0
else
  echo "ok: import networkx resolves to $SRC/networkx/__init__.py"
fi

# ---------- 0.6 interpreter-state and canary integrity -------------------------
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

# /app must contain only the harness-owned clone dir, the agent's deliverable
# and pytest's own caches: a sitecustomize.py here would be imported at python
# startup (sys.path[0] = script dir for `python3 /app/reproduce_failure.py`).
extra_app="$(find /app -mindepth 1 -maxdepth 1 \( ! -name 'src' ! -name 'reproduce_failure.py' ! -name '__pycache__' ! -name '.pytest_cache' \) 2>/dev/null | head)"
if [ -n "$extra_app" ]; then
  echo "FAIL: unexpected top-level file(s)/dir(s) in /app (possible interpreter hook): $(echo "$extra_app" | tr '\n' ' ')" >&2
  reward=0
else
  echo "ok: /app contains only the clone, the deliverable and caches"
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

check_canary /opt/golden d3b05db97dd04eafff1f25b964ec088927adaddd23b20f6748c3b3554066c5f0
check_canary /tests/hidden/case-int-keys 14be046d9330a019dc3b2df9810622ca9201787d98ad5440ae6ff8784c70dd95
check_canary /tests/hidden/case-string-keys 125480c9cac56008181435817fc3f67efed6e802bd53ea9e537918505dcb62d9

# ---------- 1. the agent's own reproduction, both directions -------------------
echo "== the agent's own reproduction =="
# Backup the agent's source, restore the pristine parent version of the one
# generator file, and require the reproduction to FAIL (it demonstrates the
# bug).  Then restore the agent's version and require it to PASS.
cp "$SRC/networkx/generators/geometric.py" /tmp/agent_geometric.py
git -C "$SRC" checkout -q -- networkx/generators/geometric.py
if ( cd /app && python3 reproduce_failure.py > /tmp/repro_pristine.out 2>&1 ); then
  echo "FAIL: the reproduction PASSED against the pristine (still buggy) generator; it is not a failing reproduction" >&2
  reward=0
else
  echo "ok: reproduction fails against the pristine generator"
fi
cp /tmp/agent_geometric.py "$SRC/networkx/generators/geometric.py"
if ( cd /app && python3 reproduce_failure.py > /tmp/repro_fixed.out 2>&1 ); then
  echo "ok: reproduction passes against the repaired tree"
else
  echo "FAIL: the reproduction still fails against the repaired tree" >&2
  tail -20 /tmp/repro_fixed.out | sed 's/^/    /' >&2
  reward=0
fi

# ---------- 2. golden: the upstream regression test -----------------------------
echo "== golden test (upstream regression test for this bug) =="
if [ ! -s /opt/golden/test_geometric.py ]; then
  echo "FAIL: golden test file missing from the image" >&2; reward=0
else
  cp /opt/golden/test_geometric.py "$SRC/networkx/generators/tests/test_geometric.py"
  # First the upstream regression test itself, by node id; then the whole
  # fix-commit module (regression test + 54 pre-existing tests).
  run_pytest "golden regression test test_S1_kappas_mean_degree_from_values" /tmp/golden_one.out \
    "networkx/generators/tests/test_geometric.py::test_S1_kappas_mean_degree_from_values" || true
  run_pytest "golden test_geometric.py (fix-commit module)" /tmp/golden.out \
    networkx/generators/tests/test_geometric.py || true
fi

# ---------- 3. the project's own existing tests ----------------------------------
echo "== the project's own existing tests =="
# Restore the tree's own version of the test module (the parent-commit bytes)
# and re-run it: the pre-existing expectations must stay green with the fix.
git -C "$SRC" checkout -q -- networkx/generators/tests/test_geometric.py
run_pytest "tree's own test_geometric.py module" /tmp/own_module.out \
  networkx/generators/tests/test_geometric.py || true

# ---------- 4. hidden cases -------------------------------------------------------
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