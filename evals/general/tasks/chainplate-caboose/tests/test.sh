#!/bin/bash
# Verifier for chainplate-caboose: an upstream-clone security task on
# pypa/setuptools. The agent must fix, in the real checkout at /app/src, a
# real vulnerability: setuptools.archive_util's extraction guard splits
# archive member names on '/' alone, so members named with backslashes
# instead of '/' (or carrying drive letters or UNC prefixes) slip past the
# '..' check and are extracted -- on Windows they resolve OUTSIDE the
# extraction directory, on POSIX they land as surprising literal backslash
# names. Unsafe members must be rejected and safe members of the same
# archive still extracted.
#
# The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the clone, the regression
#      test module the image overlaid from the fix commit is byte-identical
#      to /opt/golden, the ONLY tracked files differing from the pinned
#      commit are that overlaid test module and setuptools/archive_util.py,
#      and archive_util.py really is non-empty-diffed -- i.e. the answer was
#      found in the tree by editing it, not fetched);
#   1. runs the project's own regression suite
#      (`python3 -m pytest -q setuptools/tests/test_archive_util.py`) against
#      the repaired tree and requires the mined green state
#      '14 passed, 1 xpassed' with a zero exit code;
#   2. re-runs the task's own direct reproduction and requires that only the
#      safe member is extracted;
#   3. runs at least two authored hidden cases (tests/hidden/*/check.py)
#      that exercise the same code path with archive member names the
#      upstream regression tests do not use (UNC prefixes, drive-plus-
#      backslash names, bare second-drive letters, deep '..' chains,
#      backslashes inside relative paths, and safe exotic names that must
#      still extract byte-exactly).
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=bb1b38189eed960bdb4f4789926472d05e43d335
FIX_SHA=72974110e29d53080dcf23cfa52d9c17299dbae4
GOLDEN=/opt/golden/test_archive_util.py
GOLDEN_SHA=0bf96f6d993cb9dfca413b2078890fbe9e9d6dcb4e23ea5d4a25202c49d39970

fail() {  # fail MESSAGE
  echo "FAIL: $1" >&2
  reward=0
}

# ---------- 0a. no interpreter-level answer smuggling ------------------------
# The trial runs as root in a container shared with the verifier, so an agent
# could try to "fix" the bug through interpreter hooks instead of the deliverable
# tree: a sitecustomize.py / usercustomize.py or a stray .pth in site-packages,
# an untracked conftest.py / sitecustomize.py inside /app/src, or a PYTHONPATH
# shim. Reject all of those: the fix must live in /app/src where it can be seen.
# (The history: a sitecustomize.py carrying the fix plus a cosmetic diff to
# archive_util.py passed this verifier before this section existed.)

unset PYTHONPATH PYTHONHOME PYTHONUSERBASE PYTHONSTARTUP 2>/dev/null || true

if [ -f /opt/site-hooks-inventory.txt ]; then
  cur=$(find /usr/local/lib/python3.12/site-packages /root/.local/lib/python3.12/site-packages \
        -maxdepth 1 \( -name 'sitecustomize.py' -o -name 'usercustomize.py' -o -name '*.pth' \) \
        -printf '%f|%s|%T@\n' 2>/dev/null | sort)
  if [ "$cur" = "$(cat /opt/site-hooks-inventory.txt)" ]; then
    echo "ok: site-packages import hooks match the built image"
  else
    fail "site-packages import hooks (sitecustomize/usercustomize/*.pth) were altered"
  fi
fi

untracked=$(git -C "$SRC" status --porcelain 2>/dev/null | awk '$1=="??" {print $2}' | sed 's#/$##' | grep -v '^setuptools\.egg-info' || true)
if [ -n "$untracked" ]; then
  fail "unexpected untracked files inside /app/src (conftest/sitecustomize smuggling):"
  printf '%s\n' "$untracked" | head -5 | sed 's/^/    /' >&2
else
  echo "ok: no untracked files inside /app/src"
fi

# ---------- 0b.
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

tree_golden=$(sha256sum < "$SRC/setuptools/tests/test_archive_util.py" 2>/dev/null | cut -d' ' -f1)
opt_golden=$(sha256sum < "$GOLDEN" 2>/dev/null | cut -d' ' -f1)
if [ "$tree_golden" = "$GOLDEN_SHA" ] && [ "$opt_golden" = "$GOLDEN_SHA" ]; then
  echo "ok: setuptools/tests/test_archive_util.py is byte-identical to the upstream regression tests"
else
  fail "the regression test module was altered (tree=${tree_golden:-missing} opt=${opt_golden:-missing})"
fi

changed=$(git -C "$SRC" diff --name-only 2>/dev/null | sort)
expect=$'setuptools/archive_util.py\nsetuptools/tests/test_archive_util.py'
if [ "$changed" = "$expect" ]; then
  echo "ok: the only tracked file differing from the pinned commit besides the overlaid tests is setuptools/archive_util.py"
else
  fail "unexpected tracked changes (expected only setuptools/archive_util.py + the overlaid tests):"
  printf '%s\n' "$changed" | head -10 | sed 's/^/    /' >&2
fi

if [ -z "$(git -C "$SRC" diff -- setuptools/archive_util.py 2>/dev/null || true)" ]; then
  fail "the deliverable /app/src is unchanged (no fix was implemented)"
else
  echo "ok: setuptools/archive_util.py differs from the pinned commit"
fi

# ---------- 1. the project's own regression suite ----------------------------
echo "== the project's own regression suite =="
if [ "$reward" = 1 ]; then
  ( cd "$SRC" && python3 -m pytest -q setuptools/tests/test_archive_util.py \
      > /tmp/golden.out 2>&1 )
  rc=$?
  if [ "$rc" = 0 ] && grep -qF "14 passed, 1 xpassed" /tmp/golden.out 2>/dev/null; then
    echo "ok: setuptools/tests/test_archive_util.py: $(grep -oF '14 passed, 1 xpassed' /tmp/golden.out)"
  else
    fail "the project's own regression suite is not green (rc=$rc)"
    tail -15 /tmp/golden.out 2>/dev/null | sed 's/^/    /' >&2
  fi
fi

# ---------- 2. the direct reproduction ---------------------------------------
echo "== direct reproduction =="
if [ "$reward" = 1 ]; then
  out=$(cd "$SRC" && python3 - <<'PY'
import io
import os
import tarfile
import tempfile

from setuptools import archive_util

tmp = tempfile.mkdtemp()
tgz = os.path.join(tmp, 'malicious.tar.gz')
with tarfile.open(tgz, mode='w:gz') as t:
    for name in ['..\\escaped.txt', 'inside.txt']:
        info = tarfile.TarInfo(name)
        data = name.encode()
        info.size = len(data)
        t.addfile(info, io.BytesIO(data))
dest = os.path.join(tmp, 'dest')
archive_util.unpack_archive(tgz, dest)
names = sorted(
    os.path.relpath(os.path.join(r, f), dest)
    for r, _d, fs in os.walk(dest) for f in fs
)
print('EXTRACTED:', names)
PY
)
  if printf '%s\n' "$out" | grep -qF "EXTRACTED: ['inside.txt']"; then
    echo "ok: direct reproduction extracts only the safe member"
    printf '%s\n' "$out" | sed 's/^/    /'
  else
    fail "direct reproduction did not extract only the safe member"
    printf '%s\n' "$out" | sed 's/^/    /' >&2
  fi
fi

# ---------- 3. authored hidden cases -----------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  check="$case/check.py"
  [ -f "$check" ] || continue
  n_hidden=$((n_hidden + 1))
  cname=$(basename "$case")
  if out=$(python3 "$check" 2>&1); then
    echo "ok: hidden case $cname: $(printf '%s\n' "$out" | tail -1)"
  else
    fail "hidden case $cname"
    printf '%s\n' "$out" | tail -8 | sed 's/^/    /' >&2
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  fail "fewer than two hidden cases were exercised"
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0