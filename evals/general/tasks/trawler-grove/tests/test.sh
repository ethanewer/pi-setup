#!/bin/bash
# Verifier for trawler-grove: an upstream-clone debugging task on
# python-poetry/poetry.
#
# The agent must, in the real checkout at /app/src (pinned to the parent
# commit, fix commit unreachable), write its own failing reproduction at
# /app/repro_test.py and then fix a real upstream bug: the clone fallback
# passes explicit refs/heads/... or refs/tags/... revisions to `git
# checkout` unchanged because the intended prefix-stripping silently never
# happens. The verifier:
#   0. asserts tree provenance — HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the object store, the clone
#      has no git remotes, the working tree differs from the parent in
#      exactly one tracked source file (a CONTENT check: every tracked file
#      is hashed against the pinned commit's own blob, so
#      assume-unchanged/skip-worktree tricks cannot hide a dirty file) and
#      no stray untracked files exist; asserts the venv provenance (poetry
#      resolves to /app/src/src, the single poetry.pth hook is intact, no
#      unexpected top-level modules, venv bin scripts byte-identical to the
#      image build) and the integrity anchors (golden test sha256, pristine
#      pre-fix backend.py still the parent blob);
#   1. requires the two deliverables /app/repro_test.py and /app/summary.md;
#   2. runs the agent's own reproduction against the REPAIRED tree — must
#      pass;
#   3. runs the agent's own reproduction against a pristine PRE-FIX copy of
#      the package source (baked at /opt/prefix/src at image build time and
#      verified equal to the parent blob) — must FAIL, proving the
#      reproduction targets the real bug and is not hardcoded or vacuous;
#      the agent's fixed file is restored and verified afterwards;
#   4. plants the upstream project's own regression test for this bug
#      (tests/vcs/git/test_backend.py extracted from the fix commit at image
#      build time into /opt/golden, sha256-pinned; never part of this task
#      tree) and runs the regression case — 4/4 parametrised cases;
#   5. runs the whole planted git-backend test file (34 tests, offline) —
#      the project's own existing suite for the changed module, proving the
#      fix broke nothing else;
#   6. runs two authored hidden cases driving the same code path from ref
#      inputs the upstream regression test does not use.
#
# Reward is binary and written on every exit path (trap below).
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
# Disable user-site import injection: a usercustomize.py dropped in a
# writable HOME must never supply expected behaviour to the verifier's own
# python processes.
export PYTHONNOUSERSITE=1
# Never resolve through git replace refs: an adversarial agent could `git
# replace` the pinned parent commit and redirect rev-parse/hash comparisons
# to a forged tree. With replace refs disabled, every comparison below uses
# the real parent objects; any replace ref that exists is an instant fail.
export GIT_NO_REPLACE_OBJECTS=1
mkdir -p /logs/verifier
LOG=/logs/verifier/verifier.log
: > "$LOG"
reward=1

SRC=/app/src
VENV=/opt/poetry-venv
PARENT=b8383e3cda4e7336eb9048b1e7388b5b914a4653
FIX=3f7feee6985853ee3bda6c92465273738a94b628
GOLDEN=/opt/golden/test_backend.py
GOLDEN_SHA=c8cb85ea1fcd90f0cf5f72febcd008c0717ed580a6d350a54ea8f01b861ee561
PRISTINE=/opt/prefix/src/poetry/vcs/git/backend.py
BUGFILE=src/poetry/vcs/git/backend.py
PYTESTFLAGS=(--no-header -p no:randomly -o addopts="")

fail() {  # fail MESSAGE
  echo "FAIL: $1" >&2
  echo "FAIL: $1" >> "$LOG"
  reward=0
}

# ---------- 0a. tree provenance and scope (content hashing) ------------------
echo "== tree provenance =="
if [ ! -d "$SRC/.git" ]; then
  fail "/app/src is not a git clone"
elif [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT" ]; then
  fail "/app/src HEAD is not the pinned parent commit"
else
  echo "ok: HEAD is $PARENT"
fi

if git -C "$SRC" cat-file -e "${FIX}^{commit}" 2>/dev/null; then
  fail "the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)"
else
  echo "ok: the upstream fix commit is not present in the clone's object store"
fi

remotes=$(git -C "$SRC" remote 2>/dev/null | tr '\n' ' ')
if [ -n "$remotes" ]; then
  fail "the clone has git remotes ($remotes); it must be remote-less"
else
  echo "ok: the clone has no git remotes"
fi

replace_refs=$(git -C "$SRC" for-each-ref refs/replace --format='%(refname)' 2>/dev/null | tr '\n' ' ')
if [ -n "$replace_refs" ]; then
  fail "git replace refs present ($replace_refs); object resolution must not be redirected"
else
  echo "ok: no git replace refs"
fi

# Every tracked file must be byte-identical to the parent commit except the
# single source file where the bug lives. Hashing index oid AND worktree
# bytes catches staged-but-unmodified, assume-unchanged and skip-worktree
# tricks; gitlinks are checked at index level only.
ok=1
while IFS= read -r -d '' f; do
    if [ "$f" = "$BUGFILE" ]; then
        if git -C "$SRC" diff --quiet HEAD -- "$f" 2>/dev/null; then
            echo "tracked file unchanged (no fix implemented): $f" >> "$LOG"
            ok=0
        fi
        continue
    fi
    want=$(git -C "$SRC" rev-parse "$PARENT:$f" 2>/dev/null || true)
    if [ -z "$want" ]; then
        echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
    fi
    idx=$(git -C "$SRC" ls-files -s -- "$f" | awk '{print $2}')
    mode=$(git -C "$SRC" ls-files -s -- "$f" | awk '{print $1}')
    if [ "$idx" != "$want" ]; then
        echo "index oid mismatch for tracked file: $f" >> "$LOG"; ok=0; continue
    fi
    case "$mode" in
        160000*) : ;;  # gitlink: index-level check above is authoritative
        120000*)
            have=$(printf '%s' "$(readlink "$SRC/$f")" | git hash-object --stdin 2>/dev/null || true)
            if [ -z "$have" ] || [ "$have" != "$want" ]; then
                echo "worktree differs from parent for symlink: $f" >> "$LOG"; ok=0
            fi
            ;;
        *)
            have=$(git hash-object -- "$SRC/$f" 2>/dev/null || true)
            if [ -z "$have" ] || [ "$have" != "$want" ]; then
                echo "worktree differs from parent for tracked file: $f" >> "$LOG"; ok=0
            fi
            ;;
    esac
done < <(git -C "$SRC" ls-files -z)
while IFS= read -r -d '' f; do
    echo "untracked non-ignored file in tree: $f" >> "$LOG"; ok=0
done < <(git -C "$SRC" ls-files --others -z --exclude-standard)
if [ "$ok" != "1" ]; then
    tail -30 "$LOG" >&2
    fail "working tree differs from the pinned commit outside the bug's source file (see $LOG)"
else
    echo "ok: every tracked file except $BUGFILE matches the parent blob; no stray files"
fi

# ---------- 0b. integrity anchors -------------------------------------------
echo "== integrity anchors =="
golden_now=$(sha256sum "$GOLDEN" 2>/dev/null | cut -d' ' -f1)
if [ "$golden_now" = "$GOLDEN_SHA" ]; then
  echo "ok: golden regression test matches its pinned sha"
else
  fail "golden regression test was substituted (sha ${golden_now:-missing})"
fi

pristine_obj=$(git -C /app/src rev-parse "$PARENT:$BUGFILE" 2>/dev/null || true)
pristine_now=$(git hash-object "$PRISTINE" 2>/dev/null || true)
if [ -n "$pristine_obj" ] && [ "$pristine_now" = "$pristine_obj" ]; then
  echo "ok: pristine pre-fix backend.py is byte-identical to the parent blob"
else
  fail "pristine pre-fix backend.py was substituted (hash $pristine_now, want $pristine_obj)"
fi

# ---------- 0c. venv provenance ---------------------------------------------
echo "== venv provenance =="
sp=$(cd /tmp && "$VENV/bin/python" -c "import sysconfig; print(sysconfig.get_paths()['purelib'])")

poetry_file=$(cd /tmp && "$VENV/bin/python" -c \
  "import poetry.vcs.git.backend as m; print(m.__file__)" 2>&1)
case "$poetry_file" in
  /app/src/src/*)
    echo "ok: poetry.vcs.git.backend resolves to $poetry_file" ;;
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

# ---------- 1. deliverables --------------------------------------------------
echo "== deliverables =="
if [ -s /app/repro_test.py ]; then
  echo "ok: /app/repro_test.py present"
else
  fail "/app/repro_test.py is missing or empty"
fi
if [ -s /app/summary.md ]; then
  echo "ok: /app/summary.md present"
else
  fail "/app/summary.md is missing or empty"
fi

# ---------- 2. the agent's reproduction against the REPAIRED tree ------------
echo "== agent reproduction vs repaired tree =="
(cd /tmp && "$VENV/bin/python" -m pytest /app/repro_test.py "${PYTESTFLAGS[@]}" \
   -q > /tmp/repro_fixed.out 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
  echo "ok: agent reproduction passes on the repaired tree: $(tail -1 /tmp/repro_fixed.out)"
else
  echo "agent reproduction failed on the repaired tree (rc=$rc); output:" >> "$LOG"
  head -20 /tmp/repro_fixed.out >> "$LOG"
  fail "agent reproduction does not pass on the repaired tree (see $LOG)"
fi

# ---------- 3. the agent's reproduction against the PRISTINE tree ------------
# Swap the pristine pre-fix file over the tree, run the same reproduction,
# and require it to FAIL. Then restore the agent's fixed file and verify the
# bytes are exactly those we backed up.
echo "== agent reproduction vs pristine pre-fix tree =="
backup=/tmp/agent-backend.py
if ! cp "$SRC/$BUGFILE" "$backup"; then
  fail "cannot back up the agent's backend.py"
fi
if ! cp "$PRISTINE" "$SRC/$BUGFILE"; then
  fail "cannot plant pristine backend.py"
fi
(cd /tmp && "$VENV/bin/python" -m pytest /app/repro_test.py "${PYTESTFLAGS[@]}" \
   -q > /tmp/repro_pristine.out 2>&1)
rc=$?
if ! cp "$backup" "$SRC/$BUGFILE"; then
  fail "cannot restore the agent's backend.py"
fi
if ! cmp -s "$backup" "$SRC/$BUGFILE"; then
  fail "restored backend.py differs from the agent's file"
fi
if [ "$rc" -eq 0 ]; then
  echo "agent reproduction passed against the pristine PRE-FIX tree (expected failure); output:" >> "$LOG"
  head -20 /tmp/repro_pristine.out >> "$LOG"
  fail "agent reproduction did not fail on the pristine pre-fix tree (see $LOG)"
else
  echo "ok: agent reproduction fails on the pristine pre-fix tree (rc=$rc)"
fi

# ---------- 4. the upstream regression test (golden) -------------------------
echo "== golden regression case (project's own test file from the fix commit) =="
cp "$GOLDEN" "$SRC/tests/vcs/git/test_backend.py" \
  || fail "cannot plant the golden regression test"
(cd "$SRC" && "$VENV/bin/python" -m pytest tests/vcs/git/test_backend.py \
   -k test_clone_legacy_strips_ref_prefixes "${PYTESTFLAGS[@]}" \
   -q > /tmp/golden.out 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && grep -Eq "(^|[^0-9])4 passed" /tmp/golden.out; then
  echo "ok: golden regression case: $(tail -1 /tmp/golden.out)"
else
  echo "golden regression case failed (rc=$rc); output:" >> "$LOG"
  tail -30 /tmp/golden.out >> "$LOG"
  fail "the upstream regression test did not pass 4/4 on the repaired tree (see $LOG)"
fi

# ---------- 5. the project's own existing git-backend suite -----------------
# The planted file is the fix commit's test_backend.py: 33 pre-existing
# offline tests plus the 4-param regression case, all exercising the module
# the fix touched. A green run proves the fix broke nothing else.
echo "== the project's own git-backend suite =="
(cd "$SRC" && "$VENV/bin/python" -m pytest tests/vcs/git/test_backend.py \
   "${PYTESTFLAGS[@]}" -q > /tmp/suite.out 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && grep -Eq "(^|[^0-9])34 passed" /tmp/suite.out; then
  echo "ok: git-backend suite: $(tail -1 /tmp/suite.out)"
else
  echo "git-backend suite failed (rc=$rc); output:" >> "$LOG"
  tail -30 /tmp/suite.out >> "$LOG"
  fail "the project's own git-backend suite is not fully green (see $LOG)"
fi

# ---------- 6. authored hidden cases ----------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  if ( cd /tmp && "$VENV/bin/python" -m pytest "$case" "${PYTESTFLAGS[@]}" \
        -q > "$out" 2>&1 ); then
    echo "ok: hidden case $name: $(tail -1 "$out")"
  else
    echo "hidden case $name failed; output:" >> "$LOG"
    tail -25 "$out" >> "$LOG"
    fail "hidden case $name (see $LOG)"
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  fail "fewer than two hidden cases were exercised (got $n_hidden)"
fi

if [ "$reward" = "1" ]; then
  echo "PASS: provenance, fix-unreachable, scope, venv integrity, deliverables, reproduction both directions, upstream regression test, existing git-backend suite, hidden cases"
fi
echo "$reward" > /logs/verifier/reward.txt
exit 0