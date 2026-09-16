#!/bin/bash
# Verifier for chainplate-chartroom: an upstream-clone debugging task on
# python-poetry/poetry.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# Config.process() resolves {dotted.config.key} templates inside string
# config values, but guards substitution with `if config_value:`, so falsy
# referenced values (0, False, "") look unset and the placeholder is left
# literally unexpanded. The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable, the clone has no git remotes,
#      the working tree differs from the parent in exactly the overlaid
#      regression-test file and src/poetry/config/config.py, the overlaid
#      test file is byte-identical to the golden copy, and nothing else --
#      tracked or untracked -- appeared in the tree);
#   1. runs the project's own regression case for the bug
#      (test_config_process_resolves_falsy_values) from the repaired tree;
#   2. runs the project's own existing tests/config suite fully, proving the
#      fix broke nothing else;
#   3. runs two authored hidden cases driving the same code path from falsy
#      inputs the upstream regression test does not use: False booleans, an
#      integer zero via the config dictionary and via the POETRY_* env
#      route, and empty-string values (including inside larger templates).
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
# Disable user-site import injection: a usercustomize.py dropped in a
# writable HOME must never supply expected behaviour to the verifier's own
# python processes.
export PYTHONNOUSERSITE=1
mkdir -p /logs/verifier
reward=1

SRC=/app/src
VENV=/opt/poetry-venv
PARENT_SHA=e54180064368c2f9d9ad5ff4771d8b33538cc372
FIX_SHA=e6f1ded9902d1fa17fc74e6562cb423e84fa7752
GOLDEN=/opt/golden/test_config.py
GOLDEN_SHA=3f93019026b8546d337b53ba2dd264ff145dec187196d66b23d54d728f16359a

fail() {  # fail MESSAGE
  echo "FAIL: $1" >&2
  reward=0
}

# ---------- 0. tree provenance -----------------------------------------------
echo "== tree provenance =="
if [ ! -d "$SRC/.git" ]; then
  fail "/app/src is not a git clone"
elif [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  fail "/app/src HEAD is not the pinned parent commit"
else
  echo "ok: HEAD is $PARENT_SHA"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  fail "the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)"
else
  echo "ok: the upstream fix commit is not present in the clone"
fi

remotes=$(git -C "$SRC" remote 2>/dev/null | tr '\n' ' ')
if [ -n "$remotes" ]; then
  fail "the clone has git remotes ($remotes); it must be remote-less"
else
  echo "ok: the clone has no git remotes"
fi

changed=$(git -C "$SRC" diff --name-only HEAD 2>/dev/null | sort | paste -sd' ' -)
expected="src/poetry/config/config.py tests/config/test_config.py"
if [ "$changed" = "$expected" ]; then
  echo "ok: tracked tree differs from the pinned commit only in the fix and the overlaid regression test"
else
  fail "tracked tree differs in unexpected files: [$changed]"
fi

if [ -z "$(git -C "$SRC" diff -- src/poetry/config/config.py 2>/dev/null || true)" ]; then
  fail "the deliverable /app/src is unchanged (no fix was implemented)"
else
  echo "ok: src/poetry/config/config.py differs from the pinned commit"
fi

tree_sha=$(sha256sum < "$SRC/tests/config/test_config.py" 2>/dev/null | cut -d' ' -f1)
if [ "$tree_sha" = "$GOLDEN_SHA" ]; then
  echo "ok: tests/config/test_config.py is byte-identical to the upstream regression test"
else
  fail "tests/config/test_config.py was altered (${tree_sha:-missing})"
fi

porcelain=$(git -C "$SRC" status --porcelain --untracked-files=all 2>/dev/null || true)
bad=$(printf '%s\n' "$porcelain" | grep -vE '^[M ]{2} (src/poetry/config/config.py|tests/config/test_config.py)$' || true)
if [ -n "$bad" ]; then
  fail "unexpected working-tree entries (staged, type-changed or untracked files would let a wrapper supply the answer):"
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
else
  echo "ok: no stray staged/untracked entries in the tree"
fi

# ---------- 0b. venv provenance: the tests must exercise the delivered tree ----
# The trial runs as root and /opt/poetry-venv (unlike the git tree) is not
# covered by the tree-provenance checks, so an agent could otherwise drop an
# import-time wrapper (a *.pth hook, a sitecustomize module, a replaced
# pytest/python script) that supplies the fixed behaviour while the delivered
# tree keeps the bug. Pin the venv to the exact build-time state: poetry must
# import from /app/src/src, the site-packages top level must contain exactly
# the built .pth/.py set, and the venv bin scripts must be byte-identical to
# image build time.
echo "== venv provenance =="
sp=$(cd /tmp && "$VENV/bin/python" -c "import sysconfig; print(sysconfig.get_paths()['purelib'])")

poetry_file=$(cd /tmp && "$VENV/bin/python" -c \
  "import poetry.config.config as m; print(m.__file__)" 2>&1)
case "$poetry_file" in
  /app/src/src/*)
    echo "ok: poetry.config.config resolves to $poetry_file" ;;
  *)
    fail "poetry resolves to [$poetry_file]; the verifier must test the delivered tree, not an import-time substitute" ;;
esac

pths=$(find "$sp" -maxdepth 1 -name '*.pth' -printf '%f\n' 2>/dev/null | sort | paste -sd' ' -)
if [ "$pths" = "poetry.pth" ] && [ "$(cat "$sp/poetry.pth" 2>/dev/null)" = "/app/src/src" ]; then
  echo "ok: site-packages has exactly the editable-install hook pointing at the tree"
else
  fail "site-packages .pth state changed ([$pths]); an import-time hook must not supply the fix"
fi

pymods=$(find "$sp" -maxdepth 1 -name '*.py' -printf '%f\n' 2>/dev/null | sort | paste -sd' ' -)
if [ "$pymods" = "py.py typing_extensions.py" ]; then
  echo "ok: no unexpected top-level .py modules in site-packages"
else
  fail "unexpected site-packages python modules: [$pymods]"
fi

binhash=$( (cd "$VENV/bin" && sha256sum * 2>/dev/null | sort | md5sum | cut -d' ' -f1) )
if [ -n "$binhash" ] && [ "$binhash" = "3cf9552ca148db83c469efdac27e8891" ]; then
  echo "ok: venv bin scripts match the image build"
else
  fail "the venv bin directory changed (hash $binhash); a replaced pytest/python wrapper must not supply the fix"
fi

# ---------- 1. golden test: upstream regression case for this bug ------------
echo "== golden regression case (project's own test file) =="
if ( cd "$SRC" && "$VENV/bin/pytest" tests/config/test_config.py \
      -k test_config_process_resolves_falsy_values --no-header \
      -p no:randomly -o addopts="" > /tmp/golden.out 2>&1 ); then
  echo "ok: $(tail -1 /tmp/golden.out)"
else
  fail "the golden regression case did not pass"
  tail -25 /tmp/golden.out | sed 's/^/    /' >&2
fi

# ---------- 2. the project's own existing tests/config suite -----------------
echo "== the project's own tests/config suite =="
if ( cd "$SRC" && "$VENV/bin/pytest" tests/config/ -p no:randomly \
      -o addopts="" -q > /tmp/configdir.out 2>&1 ); then
  echo "ok: $(tail -1 /tmp/configdir.out)"
else
  fail "the project's tests/config suite is not fully green"
  tail -25 /tmp/configdir.out | sed 's/^/    /' >&2
fi

# ---------- 3. authored hidden cases -----------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  if ( cd /tmp && "$VENV/bin/pytest" "$case" -q -p no:randomly \
        -o addopts="" > "$out" 2>&1 ); then
    echo "ok: hidden case $name: $(tail -1 "$out")"
  else
    fail "hidden case $name"
    tail -25 "$out" | sed 's/^/    /' >&2
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  fail "fewer than two hidden cases were exercised"
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0