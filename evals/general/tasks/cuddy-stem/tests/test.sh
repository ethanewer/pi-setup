#!/bin/bash
# Verifier for cuddy-stem: an upstream-clone debugging task on aio-libs/aiohttp.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# a WebSocket Close frame carrying reserved status 1006 is accepted as a
# normal close instead of raising a protocol error.  The verifier:
#   0. asserts tree provenance (HEAD still the pinned parent commit, the
#      upstream fix commit not reachable, only the minimal tracked source
#      surface modified, no assume-unchanged/skip-worktree flags, no
#      untracked files);
#   1. materializes a CLEAN verdict tree /tmp/cuddy-check from the agent's
#      TRACKED state only (fresh checkout of HEAD + the single allowed diff,
#      byte-identical to /app/src's diff).  Every decisive test leg runs in
#      that clean tree, so anything untracked the agent planted to game the
#      verdict -- a root conftest.py, a pytest.py shadow, a sitecustomize
#      hook, a cwd/path marker -- is physically absent and cannot influence
#      the result.  Reproduced-bug legs run with the SAME cwd and the SAME
#      /tmp/cuddy-check path and differ only in file content, so a
#      reproduction that keys on cwd, on aiohttp.__file__, or on a planted
#      marker behaves identically in both legs and is caught.
#   2. runs the project's own regression test for this bug (extracted at
#      image build time from the upstream FIX commit into /opt/golden/ and
#      digest-pinned here) against the clean tree: it must PASS with the
#      agent's change present, and -- the linchpin -- must genuinely FAIL
#      when the change is reverted.  The negative leg uses the same
#      interpreter and the same pytest, so a fake pytest (planted in
#      site-packages or shadowing from the tree) makes both legs vacuous and
#      is caught by the "must fail" assertion.
#   3. runs the project's own existing websocket parser and writer test
#      files on the clean tree, proving the fix broke nothing else;
#   4. runs at least two authored hidden cases that exercise the same code
#      path from inputs the upstream regression test does not use (valid
#      status codes 1000-1014 and 3000-4999 stay accepted; masked and
#      extended-length Close frames carrying 1006 are rejected; a status code
#      split across chunks is rejected);
#   5. runs the agent's reproduction /app/reproduce_issue.py twice from the
#      same cwd against the clean tree: with the change present it must exit
#      0 and print "RESULT: PASS"; with the change reverted it must exit
#      non-zero and print no "RESULT: PASS".
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=14a1b5427213b5b982922627a44e4c5ae23bc0e3
FIX_SHA=20acdf440b0a39c00054d4a70ea59376b793c83d
GOLDEN=/opt/golden/test_websocket_parser.py
GOLDEN_SHA256=04e01f017f4a40a4ce4890583ee861bad9d932dd6a36993c45419a08965a68dd
REPRO=/app/reproduce_issue.py
CHECK=/tmp/cuddy-check
PATCH=/tmp/cuddy-fix.patch
PTCFG="$CHECK/setup.cfg"

# site-packages of the default interpreter, resolved dynamically so the
# isolated launchers below see the same installed packages pytest would.
SP="$(python3 -c 'import sysconfig; print(sysconfig.get_path("purelib"))' 2>/dev/null || true)"
if [ -z "$SP" ] || [ ! -d "$SP" ] || [ ! -d "$SP/pytest" ]; then
  echo "FAIL: could not resolve the site-packages directory (SP='${SP:-<empty>}')" >&2
  reward=0
fi

# run_pytest CD OUT ... -- pytest argv in the isolated interpreter; CD is
#   /tmp/cuddy-check.  Returns pytest's exit code and appends the arg list.
run_pytest () {
  local cd="$1" out="$2"; shift 2
  ( cd "$cd" && python3 -I -S - "$cd" "$SP" "$@" <<'PYEOF'
import sys
checkdir = sys.argv[1]
sp = sys.argv[2]
sys.path[:0] = [checkdir, sp]
import pytest
raise SystemExit(pytest.main(sys.argv[3:]))
PYEOF
  ) > "$out" 2>&1
}

must_pass () {  # LABEL OUT ... -- pytest leg that must exit 0
  local label="$1" out="$2"; shift 2
  if run_pytest "$CHECK" "$out" "$@"; then
    echo "ok: $label"
    return 0
  fi
  echo "FAIL: $label" >&2
  tail -40 "$out" | sed 's/^/    /' >&2
  reward=0
  return 1
}

must_fail () {  # LABEL OUT ... -- pytest leg that must exit non-zero
  local label="$1" out="$2"; shift 2
  if run_pytest "$CHECK" "$out" "$@"; then
    echo "FAIL: $label (the check passed when it must fail)" >&2
    tail -40 "$out" | sed 's/^/    /' >&2
    reward=0
    return 1
  fi
  echo "ok: $label (failed as required)"
  return 0
}

revert_reader () {
  git -C "$CHECK" checkout --quiet -- aiohttp/_websocket/reader_py.py
}

restore_reader () {
  if [ -s "$PATCH" ]; then
    git -C "$CHECK" apply --whitespace=nowarn "$PATCH" >/dev/null 2>&1
  fi
}

# ---------- 0. tree provenance -------------------------------------------------
echo "== tree provenance =="
if [ ! -d "$SRC/.git" ]; then
  echo "FAIL: /app/src is not a git checkout" >&2; reward=0
elif [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  echo "FAIL: /app/src HEAD is not the pinned parent commit" >&2; reward=0
else
  echo "ok: HEAD is $PARENT_SHA"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  echo "FAIL: the upstream fix commit is reachable from the working checkout (the answer was fetched, not implemented)" >&2
  reward=0
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
# Strict: the ONLY allowed worktree difference is a modification of
# aiohttp/_websocket/reader_py.py (staged or unstaged).  Untracked files at
# any path are rejected (a planted root conftest.py would be auto-loaded by
# pytest and could deselect every test); gitignored artifacts (__pycache__,
# .pytest_cache, *.egg-info) are invisible to porcelain and therefore
# harmless -- and in any case cannot reach the clean verdict tree below.
bad=$(printf '%s\n' "$porcelain" | grep -vE '^ ?M ? aiohttp/_websocket/reader_py.py$' || true)
if [ -n "$bad" ]; then
  echo "FAIL: unexpected worktree state (only aiohttp/_websocket/reader_py.py may be modified; no new files allowed):" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
fi
# A tracker trick: assume-unchanged / skip-worktree flags make git status and
# git diff silent about modified tracked files.  Detect and reject them.
hidden_flags=$(git -C "$SRC" ls-files -v 2>/dev/null | grep -E '^[a-z]|^S' || true)
if [ -n "$hidden_flags" ]; then
  echo "FAIL: tracked files carry assume-unchanged/skip-worktree flags (state hidden from git status):" >&2
  printf '%s\n' "$hidden_flags" | head -5 | sed 's/^/    /' >&2
  reward=0
fi
if [ -z "$(git -C "$SRC" diff HEAD -- aiohttp/_websocket/reader_py.py 2>/dev/null || true)" ]; then
  echo "FAIL: aiohttp/_websocket/reader_py.py is unchanged (no fix was implemented)" >&2
  reward=0
fi

# ---------- 1. materialize the clean verdict tree ------------------------------
echo "== clean verdict tree (materialized from tracked state only) =="
rm -rf "$CHECK" "$PATCH"
if ! git clone --quiet --local --no-hardlinks "$SRC" "$CHECK" 2>/dev/null; then
  echo "FAIL: could not materialize the clean verdict tree" >&2
  reward=0
else
  echo "ok: clean checkout materialized at $CHECK (HEAD $(git -C "$CHECK" rev-parse HEAD))"
fi

git -C "$SRC" diff HEAD -- aiohttp/_websocket/reader_py.py > "$PATCH" 2>/dev/null || true
if [ -s "$PATCH" ]; then
  if ! git -C "$CHECK" apply --check --whitespace=nowarn "$PATCH" >/dev/null 2>&1; then
    echo "FAIL: the agent's change to reader_py.py does not apply cleanly to a fresh checkout (rejected)" >&2
    reward=0
  else
    git -C "$CHECK" apply --whitespace=nowarn "$PATCH"
    # The materialized change must be byte-identical to the agent's change.
    if git -C "$CHECK" diff -- aiohttp/_websocket/reader_py.py | diff -q - "$PATCH" >/dev/null 2>&1; then
      echo "ok: agent's single-file change carried into the clean tree"
    else
      echo "FAIL: materialized change differs from /app/src's change" >&2
      reward=0
    fi
  fi
else
  echo "note: no diff to carry (provenance already flagged)" >&2
fi

# ---------- 1.5 module origin: the verdict must measure aiohttp from the tree --
echo "== module origin (isolated interpreter, clean tree) =="
if python3 -I -S - "$CHECK" "$SP" <<'PYEOF' > /tmp/origin.out 2>&1
import sys, inspect
checkdir = sys.argv[1]
sp = sys.argv[2]
sys.path[:0] = [checkdir, sp]
import aiohttp
import aiohttp._websocket.reader as rd
import aiohttp._websocket.reader_py as rpy
import pytest
af = aiohttp.__file__
rf = inspect.getsourcefile(rd.WebSocketReader)
pf = pytest.__file__
print('aiohttp file:', af)
print('WebSocketReader file:', rf)
print('reader module:', rd.WebSocketReader.__module__)
print('pytest file:', pf)
assert af.startswith(checkdir + '/'), af
assert rd.WebSocketReader is rpy.WebSocketReader, (rd.WebSocketReader, rpy.WebSocketReader)
assert rf is not None and rf.startswith(checkdir + '/'), rf
assert pf.startswith(sp + '/'), pf
PYEOF
then
  echo "ok: aiohttp + pure-Python WebSocketReader resolve under $CHECK and pytest resolves under site-packages"
  sed 's/^/    /' /tmp/origin.out
else
  echo "FAIL: module origin check on the clean tree (aiohttp must come from $CHECK, pytest from site-packages):" >&2
  cat /tmp/origin.out | sed 's/^/    /' >&2
  reward=0
fi

# ---------- 2. golden: the upstream regression test (positive + negative) ------
echo "== golden test (upstream regression test for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
elif [ "$(/usr/bin/sha256sum "$GOLDEN" | awk '{print $1}')" != "$GOLDEN_SHA256" ]; then
  echo "FAIL: $GOLDEN does not match the bytes extracted from the upstream fix commit (expected sha256 $GOLDEN_SHA256)" >&2
  reward=0
else
  cp -f "$GOLDEN" "$CHECK/tests/test_websocket_parser.py"
  must_pass "golden test_close_frame_reserved_code, change present (PASS required)" /tmp/golden-pos.out \
      "tests/test_websocket_parser.py::test_close_frame_reserved_code" \
    || true
  # Linchpin: the same test, same interpreter, same tree -- only the change
  # reverted -- must genuinely fail.  A vacuous pytest, a deselecting
  # conftest, or a hardcoded pass all fail here.
  echo "== golden negative control: change reverted, test must fail =="
  revert_reader
  must_fail "golden test_close_frame_reserved_code, change reverted (FAIL required)" /tmp/golden-neg.out \
      "tests/test_websocket_parser.py::test_close_frame_reserved_code" \
    || true
  restore_reader || { echo "FAIL: could not re-apply the agent's change after the negative control" >&2; reward=0; }
  git -C "$CHECK" checkout --quiet -- tests/test_websocket_parser.py
fi

# ---------- 3. the project's own existing websocket tests ----------------------
echo "== the project's own existing websocket tests =="
must_pass "existing tests/test_websocket_parser.py" /tmp/own1.out tests/test_websocket_parser.py \
  || true
must_pass "existing tests/test_websocket_writer.py" /tmp/own2.out tests/test_websocket_writer.py \
  || true

# ---------- 4. hidden cases -----------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  must_pass "hidden case $name" "$out" "$case" || true
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases were exercised" >&2; reward=0
fi

# ---------- 5. reproduction: same cwd, same path, only content differs ---------
echo "== reproduction: /app/reproduce_issue.py, change present (must PASS) =="
if [ ! -s "$REPRO" ]; then
  echo "FAIL: $REPRO is missing or empty (write your reproduction first)" >&2
  reward=0
else
  if ( cd "$CHECK" && python3 -I -S - "$CHECK" "$SP" <<'PYEOF' > /tmp/repro-a.out 2>&1
import sys
checkdir = sys.argv[1]
sp = sys.argv[2]
sys.path[:0] = [checkdir, sp]
import runpy
sys.argv = ['/app/reproduce_issue.py']
runpy.run_path('/app/reproduce_issue.py', run_name='__main__')
PYEOF
  ); then
    if grep -q '^RESULT: PASS' /tmp/repro-a.out; then
      echo "ok: reproduction reported RESULT: PASS with the change present"
    else
      echo "FAIL: reproduction exited 0 but did not print a line starting with 'RESULT: PASS'" >&2
      tail -20 /tmp/repro-a.out | sed 's/^/    /' >&2
      reward=0
    fi
  else
    echo "FAIL: reproduction exited non-zero with the change present (bug still present or script broken)" >&2
    tail -20 /tmp/repro-a.out | sed 's/^/    /' >&2
    reward=0
  fi

  echo "== reproduction: same cwd and path, change reverted (must fail) =="
  revert_reader
  if ( cd "$CHECK" && python3 -I -S - "$CHECK" "$SP" <<'PYEOF' > /tmp/repro-b.out 2>&1
import sys
checkdir = sys.argv[1]
sp = sys.argv[2]
sys.path[:0] = [checkdir, sp]
import runpy
sys.argv = ['/app/reproduce_issue.py']
runpy.run_path('/app/reproduce_issue.py', run_name='__main__')
PYEOF
  ); then
    echo "FAIL: reproduction exited 0 with the change reverted; it must fail while the bug is present" >&2
    tail -20 /tmp/repro-b.out | sed 's/^/    /' >&2
    reward=0
  else
    if grep -q '^RESULT: PASS' /tmp/repro-b.out; then
      echo "FAIL: reproduction printed RESULT: PASS with the change reverted (it does not detect the bug)" >&2
      reward=0
    else
      echo "ok: reproduction failed with the change reverted as required (non-zero exit, no RESULT: PASS)"
    fi
  fi
  restore_reader || { echo "FAIL: could not re-apply the agent's change after the reproduction legs" >&2; reward=0; }
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0