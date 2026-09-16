#!/bin/bash
# Verifier for berm-coaming: an upstream-clone debugging task on
# duckdb/duckdb.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# errors raised inside a list_reduce lambda surface as
#   INTERNAL Error: Scalar function "list_reduce" threw an execution error,
#   but the function is not marked as fallible - the function must call
#   SetFallible(). Error: <lambda message>
# plus a stack trace, instead of the lambda's own clean Invalid Input /
# Conversion error (list function lambda errors must surface cleanly, the
# way list_transform / list_filter already do). The agent must also deliver
# its own reproduction script /app/repro.sh, whose contract is to print
# REPRO-PASS iff a list_reduce lambda error surfaces cleanly with no
# INTERNAL Error. The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      single-commit object store does not contain the upstream fix commit
#      and holds no unreachable objects, exactly the one source file the bug
#      lives in is modified with a real diff, no assume-unchanged /
#      skip-worktree tricks, no untracked non-ignored files, /opt/golden
#      byte-intact);
#   1. deletes the project binaries and relinks them from the repaired tree
#      with the project's own build system, and requires the project's own
#      regression test (golden reduce.test, planted here from /opt/golden)
#      to pass through the project's own runner plus the whole lambdas
#      suite to stay green, and both binaries to be real ELF executables;
#   2. executes the agent's /app/repro.sh against the pre-fix engine
#      snapshot /opt/pre-fix/duckdb AND a copy of it at another path (both
#      must print REPRO-FAIL: the reproduction genuinely detects the bug)
#      and against the repaired engine (must print REPRO-PASS);
#   3. runs authored hidden cases through the repaired CLI (CLEAN rows must
#      surface the lambda's clean error with no INTERNAL Error; VALUE rows
#      must return the exact value) and runs every CLEAN row against the
#      pre-fix snapshot, requiring the INTERNAL error there (each hidden
#      check genuinely detects the bug pre-fix).
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
LOG=/logs/verifier/verifier.log
: > "$LOG"
reward=1
# Per-run scratch dir: /tmp may contain root-owned leftovers baked into the
# image at build time (e.g. /tmp/golden.out from the golden-fails-at-parent
# smoke run), and a uid-1000 trial cannot truncate those (EACCES on the shell
# redirect would abort the unittest, and a stale file would be misread as the
# current result). mktemp creates a fresh dir owned by the trial user.
SCRATCH=$(mktemp -d /tmp/berm-v-XXXXXX 2>/dev/null) || SCRATCH=/app/.verify
mkdir -p "$SCRATCH"

SRC=/app/src
PARENT_SHA=c54cb2c29b2fda8c78d278e62629bce08291daad
FIX_SHA=cf77bda5a15e7d3c8c0222a31c9ad84eec77e6c5
GOLDEN_SHA=cdbae1f393ed279bdf5c945e85c7f1d059228334e5d7944fee5369001a01778c
GOLDEN_REL=test/sql/function/list/lambdas/reduce.test
PRE_FIX=/opt/pre-fix/duckdb
FIX_FILE=extension/core_functions/scalar/list/list_reduce.cpp

fail() {  # fail MESSAGE
  echo "FAIL: $1" | tee -a "$LOG" >&2
  reward=0
}

is_elf() {  # is_elf BIN
  local magic
  magic=$(head -c 4 "$1" 2>/dev/null | od -An -tx1 | tr -d ' \n')
  [ "$magic" = "7f454c46" ]
}

# ---------- 0. tree provenance -----------------------------------------------
echo "== tree provenance =="
if [ ! -d "$SRC/.git" ]; then
  fail "/app/src is not a git clone"
else
  head=$(git -C "$SRC" rev-parse HEAD 2>/dev/null)
  if [ "$head" = "$PARENT_SHA" ]; then
    echo "ok: HEAD is $PARENT_SHA"
  else
    fail "/app/src HEAD is '$head', expected pinned parent $PARENT_SHA"
  fi
  if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
    fail "the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)"
  else
    echo "ok: the upstream fix commit is not present in the clone"
  fi
  ncommits=$(git -C "$SRC" rev-list --all --count 2>/dev/null | tr -d '[:space:]')
  if [ "$ncommits" = "1" ]; then
    echo "ok: single-commit object store ($ncommits commit)"
  else
    fail "object store has ${ncommits:-?} commits; expected exactly 1"
  fi
  unreachable=$(git -C "$SRC" fsck --no-reflogs --unreachable 2>/dev/null | wc -l)
  if [ "$unreachable" = "0" ]; then
    echo "ok: no unreachable objects in the object store"
  else
    fail "object store contains $unreachable unreachable objects"
  fi
fi

# scope: exactly the one source file the bug lives in may differ from the
# pinned commit, with a real diff; no assume-unchanged / skip-worktree
# trickery; no untracked non-ignored files.
if [ "$reward" = 1 ]; then
  changed=$(git -C "$SRC" diff HEAD --name-only 2>/dev/null | grep -v '^$' | sort)
  nchanged=$(printf '%s\n' "$changed" | grep -c . || true)
  if [ "$nchanged" = "1" ] && [ "$changed" = "$FIX_FILE" ]; then
    echo "ok: exactly one modified tracked file: $FIX_FILE"
  else
    fail "expected exactly one modified tracked file ($FIX_FILE); found ${nchanged:-0}: $(printf '%s ' $changed)"
  fi
  if git -C "$SRC" diff HEAD -- "$FIX_FILE" 2>/dev/null | grep -q '^[+-]'; then
    echo "ok: $FIX_FILE contains a real diff"
  else
    fail "$FIX_FILE has no actual change (the fix was not implemented)"
  fi
  if git -C "$SRC" ls-files -v 2>/dev/null | grep -qE '^[a-zS]'; then
    fail "assume-unchanged or skip-worktree flags found on tracked files (index trickery)"
  else
    echo "ok: no assume-unchanged / skip-worktree flags"
  fi
  untracked=$(git -C "$SRC" ls-files --others -z --exclude-standard 2>/dev/null | tr -d '\0')
  if [ -n "$untracked" ]; then
    fail "untracked non-ignored files in the tree: $(printf '%s ' $untracked)"
  else
    echo "ok: no untracked non-ignored files"
  fi
fi

# ---------- 1. rebuild from the repaired tree and run the project's tests -----
echo "== rebuild from the repaired tree =="
# Delete the project binaries and rebuild: ninja must recompile the modified
# source and relink libduckdb, the duckdb CLI and the unittest runner, so any
# binary the agent planted (wrapper script, ELF decoy, stale build) is
# replaced by one freshly linked from the agent's actual sources.
if ( cd "$SRC" \
     && rm -f build/release/duckdb build/release/test/unittest \
     && touch "$FIX_FILE" \
     && ninja -C build/release -j2 > "$SCRATCH/rebuild.log" 2>&1 ); then
  echo "ok: incremental rebuild (forced recompile + relink) succeeded"
else
  fail "incremental rebuild failed"
  tail -40 "$SCRATCH/rebuild.log" 2>/dev/null | sed 's/^/    /' >&2 || true
fi

for bin in "$SRC/build/release/duckdb" "$SRC/build/release/test/unittest"; do
  if [ -f "$bin" ] && is_elf "$bin"; then
    echo "ok: $bin is a real ELF executable"
  else
    fail "$bin is not a real ELF executable: $(ls -l "$bin" 2>/dev/null | awk '{print $1, $5}' || echo missing)"
  fi
done

echo "== the project's own regression test for this bug (golden) =="
if [ "$reward" = 1 ]; then
  gsha=$(sha256sum /opt/golden/reduce.test 2>/dev/null | cut -d' ' -f1)
  if [ "$gsha" = "$GOLDEN_SHA" ]; then
    echo "ok: /opt/golden/reduce.test byte-intact (sha256 $GOLDEN_SHA)"
    rm -f "$SRC/$GOLDEN_REL" && cp /opt/golden/reduce.test "$SRC/$GOLDEN_REL" || fail "cannot plant golden regression test"
    ( cd "$SRC" && build/release/test/unittest "$GOLDEN_REL" > "$SCRATCH/golden.out" 2>&1 )
    if grep -qE "All tests passed" "$SCRATCH/golden.out" 2>/dev/null; then
      echo "ok: golden regression test passed end to end"
    else
      fail "the golden regression test did not pass"
      tail -25 "$SCRATCH/golden.out" 2>/dev/null | sed 's/^/    /' >&2 || true
    fi
    # leave the working tree exactly as the agent delivered it
    git -C "$SRC" restore --worktree --source=HEAD -- "$GOLDEN_REL" 2>/dev/null || true
  else
    fail "/opt/golden/reduce.test was tampered with (sha256 ${gsha:-missing})"
  fi
fi

echo "== the project's own lambdas suites =="
if [ "$reward" = 1 ]; then
  ( cd "$SRC" && build/release/test/unittest "test/sql/function/list/lambdas/*" > "$SCRATCH/lambdas.out" 2>&1 )
  if grep -qE "All tests passed" "$SCRATCH/lambdas.out" 2>/dev/null; then
    echo "ok: test/sql/function/list/lambdas/* green"
  else
    fail "the project's lambdas suites are not green"
    tail -25 "$SCRATCH/lambdas.out" 2>/dev/null | sed 's/^/    /' >&2 || true
  fi
fi

echo "== deliverable: the agent's change summary =="
if [ -s /app/summary.md ]; then
  echo "ok: /app/summary.md exists and is non-empty"
else
  fail "/app/summary.md is missing or empty"
fi

# ---------- 2. the agent's own reproduction, both directions ------------------
echo "== /app/repro.sh against the pre-fix engine and the repaired engine =="
if [ ! -x /app/repro.sh ]; then
  fail "/app/repro.sh is missing or not executable"
elif [ "$reward" = 1 ]; then
  # pre-fix snapshot, and a copy at a different path (a repro that cheats on
  # the literal path string is caught by the second invocation)
  cp "$PRE_FIX" "$SCRATCH/pre-fix-copy" 2>/dev/null && chmod +x "$SCRATCH/pre-fix-copy"
  for pf in "$PRE_FIX" "$SCRATCH/pre-fix-copy"; do
    preout=$(bash /app/repro.sh "$pf" 2>&1 || true)
    if printf '%s\n' "$preout" | grep -q "REPRO-PASS"; then
      fail "/app/repro.sh printed REPRO-PASS on the pre-fix engine ($pf) - it does not detect the bug"
    else
      echo "ok: /app/repro.sh detects the bug on the pre-fix engine ($pf)"
    fi
  done
  fixout=$(bash /app/repro.sh 2>&1 || true)
  if printf '%s\n' "$fixout" | grep -q "REPRO-PASS"; then
    echo "ok: /app/repro.sh passes against the repaired engine"
  else
    fail "/app/repro.sh did not print REPRO-PASS against the repaired engine: $(printf '%s' "$fixout" | head -3 | tr '\n' ' ')"
  fi
fi

# ---------- 3. authored hidden cases -----------------------------------------
echo "== hidden cases =="
n_hidden=0
n_failed=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  qf="$case"queries.txt
  [ -f "$qf" ] || { fail "hidden case $(basename "$case") has no queries.txt"; n_failed=$((n_failed+1)); continue; }
  n_hidden=$((n_hidden + 1))
  lineno=0
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    line=$(printf '%s' "$line" | sed 's/[[:space:]]*$//')
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    q=${line%%$'\t'*}
    expect=${line#*$'\t'}
    case "$expect" in
      CLEAN:*)
        want=${expect#CLEAN:}
        # repaired engine: clean error containing the expected text, no INTERNAL
        r_out=$("$SRC/build/release/duckdb" -noheader -csv -c "$q" 2>&1)
        if printf '%s\n' "$r_out" | grep -q "INTERNAL Error"; then
          fail "hidden $(basename "$case") line $lineno: repaired engine still reports an INTERNAL error"
          n_failed=$((n_failed+1))
        elif printf '%s\n' "$r_out" | grep -qF -- "$want"; then
          echo "ok: hidden $(basename "$case") line $lineno clean error contains '$want'"
        else
          fail "hidden $(basename "$case") line $lineno: repaired engine output does not contain '$want': $(printf '%s' "$r_out" | head -1)"
          n_failed=$((n_failed+1))
        fi
        # pre-fix engine must show the INTERNAL error for this input (bites)
        p_out=$("$PRE_FIX" -noheader -csv -c "$q" 2>&1)
        if printf '%s\n' "$p_out" | grep -q "INTERNAL Error"; then
          echo "ok: hidden $(basename "$case") line $lineno detects the bug pre-fix (INTERNAL error)"
        else
          fail "hidden $(basename "$case") line $lineno: pre-fix engine does not produce the INTERNAL error (this check does not detect the bug)"
          n_failed=$((n_failed+1))
        fi
        ;;
      VALUE:*)
        want=${expect#VALUE:}
        r_val=$(printf '%s\n' "$("$SRC/build/release/duckdb" -noheader -csv -c "$q" 2>&1)" | grep -v '^$' | head -1)
        p_val=$(printf '%s\n' "$("$PRE_FIX" -noheader -csv -c "$q" 2>&1)" | grep -v '^$' | head -1)
        if [ "$r_val" = "$want" ] && [ "$p_val" = "$want" ]; then
          echo "ok: hidden $(basename "$case") line $lineno value '$want' on both engines"
        else
          fail "hidden $(basename "$case") line $lineno: repaired='${r_val:-<empty>}' pre-fix='${p_val:-<empty>}', expected '$want' on both"
          n_failed=$((n_failed+1))
        fi
        ;;
      *) fail "hidden $(basename "$case") line $lineno: bad expectation '$expect'"; n_failed=$((n_failed+1)) ;;
    esac
  done < "$qf"
done
if [ "$n_hidden" -lt 2 ]; then
  fail "fewer than two hidden cases were exercised"
fi

echo
echo "hidden cases exercised: $n_hidden, failed lines: $n_failed"
echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0