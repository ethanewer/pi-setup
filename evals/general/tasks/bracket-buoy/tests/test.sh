#!/bin/bash
# Verifier for bracket-buoy: an upstream-clone debugging task on psutil.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# a single-host /32 (or /128) network has no broadcast address, but the tree
# reports the host's own address as the broadcast. The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, only the
#      minimal source surface is modified, no new files inside psutil/);
#   1. runs the project's own regression test for this bug, extracted at
#      image build time from the fix commit into /opt/golden/;
#   2. runs the project's own existing tests (tests/test_misc.py and the
#      net_if_addrs / net_if_stats slice of tests/test_system.py), proving
#      the fix broke nothing else;
#   3. runs two authored hidden cases over inputs the upstream test does not
#      use (other /32 IPv4 and /128 IPv6 single-host addresses, and a guard
#      that ordinary prefixes keep their real broadcasts).
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=8a5d53df33e28831f4833803b89e40e857d5632d
FIX_SHA=ef3d9af1062e3e5d59e431e957b75fd4287b053e
GOLDEN=/opt/golden/test_misc.py

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

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
# Only the two fix files may change. Untracked entries are rejected except
# inert cache/build artifacts that an honest agent's tooling may leave behind
# (.pytest_cache/, .coverage, .mypy_cache/, .ruff_cache/ are not executed by
# anything in the verifier); anything else -- a conftest.py, a pytest.ini, a
# patched helper -- fails the task.
bad=$(printf '%s\n' "$porcelain" \
  | grep -v '^ M psutil/__init__.py$' \
  | grep -v '^ M psutil/_common.py$' \
  | grep -vE '^\?\? (\.pytest_cache/|\.coverage$|\.mypy_cache/|\.ruff_cache/)' \
  || true)
if [ -n "$bad" ]; then
  echo "FAIL: unexpected working-tree changes (only psutil/_common.py and/or psutil/__init__.py may be modified; no other files may be added, deleted, renamed or staged):" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
fi
newpkg=$(printf '%s\n' "$porcelain" | grep '^?? psutil/' || true)
if [ -n "$newpkg" ]; then
  echo "FAIL: new files were added inside the psutil package:" >&2
  printf '%s\n' "$newpkg" | head -5 | sed 's/^/    /' >&2
  reward=0
fi
if [ -z "$(git -C "$SRC" diff -- psutil/_common.py psutil/__init__.py 2>/dev/null || true)" ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2
  reward=0
fi

AGENT_STATE=$(git -C "$SRC" status --porcelain 2>/dev/null || true)

# ---------- 0b. module provenance: the loaded code must BE the /app/src source --
# an interception wrapper (sitecustomize.py, a .pth hook, a shadow package in
# site-packages...) can make every test below pass against a wrapper while the
# checked-out tree stays buggy. Since the wrapper's bytecode must differ from
# the tree's to change behaviour, compare the code object each loaded function
# actually executes against a fresh compile of the current /app/src file.
# Any wrapper that changes behaviour in the loaded module is thereby detected.
echo "== module provenance (loaded psutil must execute /app/src code) =="
if ( cd "$SRC" && python3 - <<'PYEOF'
import pathlib
import types
import psutil
import psutil._common as c


def _consts_equal(a, b):
    if len(a) != len(b):
        return False
    for x, y in zip(a, b):
        if isinstance(x, types.CodeType) or isinstance(y, types.CodeType):
            if not (isinstance(x, types.CodeType) and isinstance(y, types.CodeType)):
                return False
            if x.co_code != y.co_code or x.co_consts != y.co_consts:
                return False
        else:
            if x != y:
                return False
    return True


def matches(name, path, mod):
    src = pathlib.Path(path).read_text()
    compiled = compile(src, path, 'exec')
    disk_fn = None
    for const in compiled.co_consts:
        if isinstance(const, types.CodeType) and const.co_name == name:
            disk_fn = const
            break
    if disk_fn is None:
        print('%s: function not found in %s' % (name, path))
        return False
    loaded = getattr(mod, name).__code__
    fields = ['co_argcount', 'co_posonlyargcount', 'co_kwonlyargcount',
              'co_flags', 'co_firstlineno', 'co_qualname', 'co_filename',
              'co_code', 'co_names', 'co_varnames', 'co_freevars',
              'co_cellvars']
    for f in fields:
        if getattr(disk_fn, f) != getattr(loaded, f):
            print('%s: field %s differs between the loaded module and %s'
                  % (name, f, path))
            return False
    if not _consts_equal(disk_fn.co_consts, loaded.co_consts):
        print('%s: co_consts differ between the loaded module and %s' % (name, path))
        return False
    return True

ok = True
ok &= matches('broadcast_addr', '/app/src/psutil/_common.py', c)
ok &= matches('net_if_addrs', '/app/src/psutil/__init__.py', psutil)
if not ok:
    raise SystemExit('module provenance mismatch')
print('ok: loaded broadcast_addr()/net_if_addrs() execute the code compiled from /app/src')
PYEOF
); then
  :
else
  echo "FAIL: a loaded psutil function is not the code compiled from /app/src (an interception wrapper is present)" >&2
  reward=0
fi

# ---------- 1. golden: the upstream regression test ---------------------------
echo "== golden test (upstream regression test for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
else
  # The golden module uses relative imports against the project's own tests
  # package, so it must live inside /app/src/tests while it is collected.
  # It is removed again afterwards; provenance is checked below.
  # The digest is recorded here (from the fix commit at build time) so that an
  # agent cannot defuse the regression test by editing the writable
  # /opt/golden copy: a tampered golden fails this check.
  case "$(sha256sum "$GOLDEN" 2>/dev/null | awk '{print $1}')" in
    808819ba3dfdb18974f38d3dcd0ae47c1e62b1584ea9d22315ef11a1d5ca231c)
      ;;
    *)
      echo "FAIL: /opt/golden/test_misc.py digest mismatch (tampered with, or not the fix commit's file)" >&2
      reward=0
      ;;
  esac
  cp "$GOLDEN" "$SRC/tests/test_golden_broadcast.py"
  run_pytest "golden test_broadcast_addr_single_host" /tmp/golden.out \
    tests/test_golden_broadcast.py::TestCommonModule::test_broadcast_addr_single_host \
    || true
  rm -f "$SRC/tests/test_golden_broadcast.py"
fi

after=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
if [ "$after" != "$AGENT_STATE" ]; then
  echo "FAIL: the working tree differs from the agent's submission state after the golden run (a file was left behind or modified)" >&2
  diff <(printf '%s\n' "$after") <(printf '%s\n' "$AGENT_STATE") | head -10 | sed 's/^/    /' >&2
  reward=0
fi

# ---------- 2. the project's own existing tests -------------------------------
echo "== the project's own existing tests =="
run_pytest "own tests/test_misc.py (excl. setup.py subprocess tests)" /tmp/own-misc.out \
  tests/test_misc.py -k "not TestSetupPy" \
  || true
run_pytest "own tests/test_system.py net slice" /tmp/own-net.out \
  tests/test_system.py -k "net_if_addrs or net_if_stats" \
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