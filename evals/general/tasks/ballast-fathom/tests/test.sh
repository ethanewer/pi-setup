#!/bin/bash
# ballast-fathom verifier.
#
# Proves the agent repaired the real upstream tree:
#   1. provenance  - /app/src is the upstream git/git clone at the parent
#                    commit (or a descendant whose parent == parent), and the
#                    upstream fix commit object is ABSENT from its object store,
#                    so the fix could not have been copied from a pre-shipped
#                    commit.
#   2. rebuild     - touch the canonical defect file and `make -j1` so the
#                    binary is provably derived from the delivered SOURCE, then
#                    confirm it is a real ELF binary.
#   3. golden      - run the project's OWN regression test for this fix (the
#                    fix-commit t/t3905-stash-include-untracked.sh, extracted to
#                    /opt/golden) against the rebuilt tree: all 26 tests pass.
#   4. own suite   - the tree's own general stash suite t3903-stash.sh must
#                    still pass (nothing else broke).
#   5. hidden      - at least two authored hidden cases exercising the same code
#                    path from inputs the upstream test never uses.
#   6. diagnosis   - /app/diagnosis.md names the defective file and the cause.
# Reward is binary: every check must pass.

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

SRC=/app/src
GITBIN=$SRC/git
PARENT=7b556aa4b80ddfedb3de25e8787acd6c69d8799c
FIX=1366c78c239e7abb24d5b74cedf237f82125492d
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
# The image ships NO fix-commit bytes (the golden test is extracted from a
# throwaway clone that is deleted), so the fix commit object cannot be present
# unless the agent fetched it over the network. A fetch followed by applying
# the real fix is a genuine repair and must be accepted; only the combination
# (fix object present AND builtin/stash.c still unfixed) is a provenance break.
if git --git-dir="$SRC/.git" cat-file -e "${FIX}^{commit}" 2>/dev/null; then
  if grep -q 'ps.items\[i\].match' "$SRC/builtin/stash.c" 2>/dev/null; then
    fail "upstream fix commit object present while builtin/stash.c is still unfixed (repair must come from the agent's own source change)"
  else
    echo "   note: upstream fix commit object present but the delivered source carries the repair; accepted"
  fi
fi
origin=$(git -C "$SRC" config --get remote.origin.url 2>/dev/null || true)
case "$origin" in
  *github.com/git/git.git|*github.com/git/git) : ;;
  *) fail "remote origin is not the upstream git/git (got '$origin')" ;;
esac

# ---------- 2. rebuild from source ----------
echo "== rebuild from tree (touch + make -j1) =="
if ! ( cd "$SRC" && touch builtin/stash.c && make -j1 > /tmp/verifier-build.log 2>&1 ); then
  echo "   build failed; tail:"; tail -15 /tmp/verifier-build.log | sed 's/^/     | /'
  fail "incremental build from the tree failed"
fi
if [ ! -x "$GITBIN" ]; then fail "no executable /app/src/git after build"; fi
if [ "$(head -c4 "$GITBIN" 2>/dev/null)" != "$(printf '\x7fELF')" ]; then
  fail "/app/src/git is not an ELF executable (planted wrapper?)"
fi
# confirm the canonical file was actually recompiled into this binary
if ! grep -q 'builtin/stash.o' /tmp/verifier-build.log; then
  fail "build log does not show builtin/stash.o being (re)compiled"
fi

# ---------- 3. golden regression test (project's own, from the fix commit) ----------
echo "== golden: fix-commit t3905-stash-include-untracked.sh =="
if [ ! -f /opt/golden/t3905-stash-include-untracked.sh ]; then fail "golden test missing"; fi
cp /opt/golden/t3905-stash-include-untracked.sh "$SRC/t/t3905-stash-include-untracked.sh"
(
  cd "$SRC/t" || exit 1
  ./t3905-stash-include-untracked.sh > /tmp/verifier-t3905.log 2>&1
)
t3905_rc=$?
# Ignore "not ok ... # TODO known breakage" lines: those are the project's own
# documented EXPECTED failures (test_expect_failure) and are not regressions.
notok_total=$(grep -c '^not ok' /tmp/verifier-t3905.log 2>/dev/null || true)
notok_todo=$(grep '^not ok' /tmp/verifier-t3905.log 2>/dev/null | grep -c '# TODO' || true)
notok=$(( ${notok_total:-0} - ${notok_todo:-0} ))
if [ "$t3905_rc" -ne 0 ] || [ "${notok:-0}" -ne 0 ]; then
  echo "   golden suite failed rc=$t3905_rc real-not-ok=$notok; tail:"
  grep -E 'not ok|error|fatal' /tmp/verifier-t3905.log | tail -6 | sed 's/^/     | /'
  fail "golden t3905 did not fully pass"
else
  echo "   ok: t3905 passed (incl. globs case)"
  grep -q '^ok 26 - stash -u with globs' /tmp/verifier-t3905.log \
    && echo "   ok: globs case is ok" \
    || fail "golden t3905 passed but globs case not reported ok"
fi

# ---------- 4. the tree's own stash suite ----------
echo "== own suite: t3903-stash.sh =="
(
  cd "$SRC/t" || exit 1
  ./t3903-stash.sh > /tmp/verifier-t3903.log 2>&1
)
t3903_rc=$?
notok3_total=$(grep -c '^not ok' /tmp/verifier-t3903.log 2>/dev/null || true)
notok3_todo=$(grep '^not ok' /tmp/verifier-t3903.log 2>/dev/null | grep -c '# TODO' || true)
notok3=$(( ${notok3_total:-0} - ${notok3_todo:-0} ))
if [ "$t3903_rc" -ne 0 ] || [ "${notok3:-0}" -ne 0 ]; then
  echo "   t3903 failed rc=$t3903_rc real-not-ok=$notok3; tail:"
  grep -E 'not ok|error|fatal' /tmp/verifier-t3903.log | tail -6 | sed 's/^/     | /'
  fail "own stash suite t3903-stash.sh did not fully pass"
else
  echo "   ok: t3903-stash.sh passed ($notok3_todo TODO expected-failures tolerated)"
fi

# ---------- 5. hidden cases ----------
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

# ---------- 6. diagnosis ----------
echo "== diagnosis =="
if [ ! -f /app/diagnosis.md ]; then
  fail "deliverable /app/diagnosis.md missing"
elif ! grep -q 'builtin/stash\.c' /app/diagnosis.md; then
  fail "/app/diagnosis.md does not name the defective file builtin/stash.c"
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
echo "ALL CHECKS PASSED: provenance clean, tree rebuilt, golden+own suites green, hidden cases pass, diagnosis complete."
echo 1 > /logs/verifier/reward.txt
exit 0
