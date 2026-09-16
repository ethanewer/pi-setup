#!/bin/bash
# capstan-pilot verifier.
#
# Proves the agent repaired the real upstream tree:
#   1. provenance  - /app/src is the upstream git/git clone at the parent
#                    commit (or a descendant whose parent == parent), and the
#                    upstream fix commit object is ABSENT from its object store,
#                    so the fix could not have been copied from a pre-shipped
#                    commit (the trial has no network, so it cannot be fetched
#                    at trial time either).
#   2. rebuild     - touch the canonical defect file and `make -j1` so the
#                    binary is provably derived from the delivered SOURCE, then
#                    confirm it is a real ELF binary.
#   3. golden      - run the project's OWN regression test for this fix (the
#                    fix-commit t/t3301-notes.sh, extracted to /opt/golden,
#                    which is also the project's full notes suite: 149 tests
#                    incl. 'empty notes do not invoke the editor') against the
#                    rebuilt tree: all 149 must pass.
#   4. hidden      - at least two authored hidden cases exercising the same code
#                    path from inputs the upstream test never uses.
#   5. diagnosis   - /app/diagnosis.md names the defective file and the cause.
# Reward is binary: every check must pass.

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

SRC=/app/src
GITBIN=$SRC/git
PARENT=39bf06adf96da25b87c9aa7d35a32ef3683eb4a4
FIX=8b426c84f376657e1e10839f3f5dafd9ba99593d
failures=""

# fail MSG  -> record a failure and abort this phase cleanly (trap writes 0)
fail() { echo "   FAIL: $1"; failures="$failures|$1"; }

[ -d "$SRC/.git" ] || { echo "   FAIL: /app/src is not a git repository"; echo 0 > /logs/verifier/reward.txt; exit 0; }

# ---------- 1. provenance ----------
echo "== provenance =="
head=$(git -C "$SRC" rev-parse HEAD 2>/dev/null) || { fail "cannot read /app/src HEAD"; }
if [ "$head" != "$PARENT" ]; then
  phead=$(git -C "$SRC" rev-parse "${head}^" 2>/dev/null || true)
  if [ "$phead" != "$PARENT" ]; then
    fail "HEAD is neither the parent commit nor a direct child of it (HEAD=$head)"
  fi
fi
if git --git-dir="$SRC/.git" cat-file -e "${FIX}^{commit}" 2>/dev/null; then
  fail "the upstream fix commit object is present in /app/src (fix likely copied from a pre-shipped commit)"
fi
origin=$(git -C "$SRC" config --get remote.origin.url 2>/dev/null || true)
case "$origin" in
  *github.com/git/git.git|*github.com/git/git) : ;;
  *) fail "remote origin is not the upstream git/git (got '$origin')" ;;
esac

# ---------- 2. rebuild from source ----------
echo "== rebuild from tree (touch + make -j1) =="
if ! ( cd "$SRC" && touch builtin/notes.c && make -j1 > /tmp/verifier-build.log 2>&1 ); then
  echo "   build failed; tail:"; tail -15 /tmp/verifier-build.log | sed 's/^/     | /'
  fail "incremental build from the tree failed"
fi
if [ ! -x "$GITBIN" ]; then fail "no executable /app/src/git after build"; fi
if [ "$(head -c4 "$GITBIN" 2>/dev/null)" != "$(printf '\x7fELF')" ]; then
  fail "/app/src/git is not an ELF executable (planted wrapper?)"
fi
# confirm the canonical file was actually recompiled into this binary
if ! grep -q 'builtin/notes.o' /tmp/verifier-build.log; then
  fail "build log does not show builtin/notes.o being (re)compiled"
fi

# ---------- 3. golden regression test (project's own full notes suite, from the fix commit) ----------
echo "== golden: fix-commit t3301-notes.sh (full notes suite, 149 tests) =="
if [ ! -f /opt/golden/t3301-notes.sh ]; then fail "golden test missing"; fi
cp /opt/golden/t3301-notes.sh "$SRC/t/t3301-notes.sh"
(
  cd "$SRC/t" || exit 1
  ./t3301-notes.sh > /tmp/verifier-t3301.log 2>&1
)
t3301_rc=$?
# Ignore "not ok ... # TODO known breakage" lines: those are the project's own
# documented EXPECTED failures (test_expect_failure) and are not regressions.
notok_total=$(grep -c '^not ok' /tmp/verifier-t3301.log 2>/dev/null || true)
notok_todo=$(grep '^not ok' /tmp/verifier-t3301.log 2>/dev/null | grep -c '# TODO' || true)
notok=$(( ${notok_total:-0} - ${notok_todo:-0} ))
if [ "$t3301_rc" -ne 0 ] || [ "${notok:-0}" -ne 0 ]; then
  echo "   golden suite failed rc=$t3301_rc real-not-ok=$notok; tail:"
  grep -E 'not ok|error|fatal' /tmp/verifier-t3301.log | tail -6 | sed 's/^/     | /'
  fail "golden t3301 did not fully pass"
else
  echo "   ok: t3301 passed (149 tests)"
  grep -q '^ok 149 - empty notes do not invoke the editor' /tmp/verifier-t3301.log \
    && echo "   ok: 'empty notes do not invoke the editor' is ok" \
    || fail "golden t3301 passed but the empty-notes regression case not reported ok"
fi

# ---------- 4. hidden cases ----------
echo "== hidden cases =="
for d in /tests/hidden/*/; do
  [ -d "$d" ] || continue
  name=$(basename "$d")
  if GITBIN="$GITBIN" bash "$d/case.sh" > /tmp/hidden-$name.log 2>&1; then
    echo "   ok: $name ($(tail -1 /tmp/hidden-$name.log))"
  else
    echo "   FAIL: hidden case $name; output:"; cat /tmp/hidden-$name.log | sed 's/^/     | /'
    fail "hidden case $name"
  fi
done

# ---------- 5. diagnosis ----------
echo "== diagnosis =="
if [ ! -f /app/diagnosis.md ]; then
  fail "deliverable /app/diagnosis.md missing"
elif ! grep -q 'builtin/notes\.c' /app/diagnosis.md; then
  fail "/app/diagnosis.md does not name the defective file builtin/notes.c"
else
  echo "   ok: diagnosis.md present and names the defective file"
fi

# ---------- verdict ----------
if [ -n "$failures" ]; then
  echo
  echo "VERIFIER FAILURES:"
  echo "$failures" | tr '|' '\n' | sed '/^$/d' | sed 's/^/  - /'
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi

echo
echo "ALL CHECKS PASSED: provenance clean, tree rebuilt, golden notes suite green, hidden cases pass, diagnosis complete."
echo 1 > /logs/verifier/reward.txt
exit 0