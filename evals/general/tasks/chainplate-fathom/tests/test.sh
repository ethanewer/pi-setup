#!/bin/bash
# ---------------------------------------------------------------------------
# Verifier for chainplate-fathom: an upstream-clone debugging task on
# semgrep/semgrep. The agent must fix, in the real checkout at /app/src, a
# real upstream bug: get_project_url() returns the remote URL verbatim,
# leaking GitLab CI job tokens embedded in the remote URL into published
# rule metadata. The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      object store holds exactly that one commit so nothing was fetched,
#      the upstream fix commit is not reachable, the tracked working tree
#      differs from the pinned commit only in cli/src/semgrep/git.py, that
#      module was actually changed, and the installed semgrep package
#      resolves to /app/src);
#   1. runs the project's own regression test for the bug (extracted from
#      the upstream fix commit into /opt/golden at image-build time) with
#      the project's own pytest runner: clean_project_url must exist and
#      rewrite the GitLab CI token URL to the bare URL;
#   2. runs the project's existing unit test tests/unit/test_baseline.py,
#      which drives BaselineHandler / git_check_output / get_git_root_path /
#      git worktree machinery of the same module, proving the fix broke
#      nothing else;
#   3. runs two authored hidden cases: end-to-end get_project_url() against
#      real throwaway git repos with GitLab job-token / PAT / port-bearing
#      URLs the upstream test does not use, and direct clean_project_url()
#      contract vectors (password with @, percent-encoded password chars,
#      bare IPv4 host, explicit port kept, clean URLs untouched, ssh://
#      git@host form untouched). All hidden expectations were checked
#      against the upstream implementation's exact behaviour.
#
# Reward is binary and written on every exit path (trap below).
# ---------------------------------------------------------------------------
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
# Neutralize user-site-packages smuggling: an agent could otherwise plant a
# working implementation in ~/.local/lib/python3.12/site-packages/sitecustomize.py
# (imported by every python process) and leave the deliverable unfixed. All
# packages this task needs (semgrep editable install, pytest) live in the
# system site-packages, so this changes nothing for honest solutions.
export PYTHONNOUSERSITE=1
mkdir -p /logs/verifier
reward=1

SRC=/app/src
CLI="$SRC/cli"
PY=python3
PARENT_SHA=a8b650dffe910d7b8903fe05ceeb75fdc7983197
FIX_SHA=e3062fc251448ffcf16a38245e5e6a8dca894df5
GOLDEN=/opt/golden/test_clean_project_url.py

fail() {  # fail "MESSAGE"
  echo "FAIL: $1" >&2
  reward=0
}

# ---------- 0. tree provenance ----------------------------------------------
echo "== 0. tree provenance =="
if [ -d "$SRC/.git" ]; then
  echo "ok: /app/src is a git clone"
else
  fail "/app/src is not a git clone"
fi

head=$(git -C "$SRC" rev-parse HEAD 2>/dev/null || true)
if [ "$head" = "$PARENT_SHA" ]; then
  echo "ok: HEAD is the pinned parent commit"
else
  fail "HEAD is ${head:-<unreadable>}, expected the pinned parent commit"
fi

ncommits=$(git -C "$SRC" rev-list --all --count 2>/dev/null || true)
if [ "$ncommits" = "1" ]; then
  echo "ok: object store holds exactly the one pinned commit"
else
  fail "object store holds ${ncommits:-<unreadable>} commits; expected exactly 1"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  fail "the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)"
else
  echo "ok: the upstream fix commit is not present in the clone"
fi

status=$(git -C "$SRC" status --porcelain --untracked-files=no 2>/dev/null || true)
if [ "$status" = " M cli/src/semgrep/git.py" ]; then
  echo "ok: tracked working tree differs from the pinned commit only in cli/src/semgrep/git.py"
else
  fail "tracked working tree differs in unexpected files:"
  printf '%s\n' "$status" | head -10 | sed 's/^/    /' >&2
fi

diffout=$(git -C "$SRC" diff -- cli/src/semgrep/git.py 2>/dev/null || true)
if [ -n "$diffout" ]; then
  echo "ok: the deliverable /app/src was actually modified"
else
  fail "the deliverable /app/src is unchanged (no fix was implemented)"
fi
# The fix must live IN the deliverable, not beside it: the tracked diff of
# the module must itself define clean_project_url, and get_project_url must
# route through it. A trivial comment/edit plus a smuggled implementation
# (sitecustomize, conftest, wrapper) must not score.
if printf '%s\n' "$diffout" | grep -q 'def clean_project_url'; then
  echo "ok: the git.py diff itself defines clean_project_url (fix is in the deliverable)"
else
  fail "git.py was changed but the diff does not define clean_project_url; the fix is not in the deliverable"
fi
if [ "$(grep -c 'clean_project_url' "$SRC/cli/src/semgrep/git.py" 2>/dev/null || echo 0)" -ge 2 ]; then
  echo "ok: git.py both defines and uses clean_project_url"
else
  fail "get_project_url does not actually use clean_project_url in the deliverable"
fi

others=$(git -C "$SRC" ls-files --others --exclude-standard 2>/dev/null || true)
if [ -z "$others" ]; then
  echo "ok: no untracked files were added to the repository"
else
  fail "untracked files were added to the repository:"
  printf '%s\n' "$others" | head -10 | sed 's/^/    /' >&2
fi

imp=$("$PY" -c 'import semgrep; print(semgrep.__file__)' 2>/dev/null || true)
case "$imp" in
  /app/src/cli/src/semgrep/__init__.py)
    echo "ok: the installed semgrep package resolves to the checked-out tree" ;;
  *)
    fail "imported semgrep does not resolve to /app/src/cli/src (got ${imp:-<unimportable>})" ;;
esac

# ---------- 1. the project's own regression test for this bug ---------------
echo "== 1. upstream regression test (/opt/golden/test_clean_project_url.py) =="
if ( cd "$CLI" && "$PY" -m pytest -p no:cacheprovider -q "$GOLDEN" > /tmp/golden.log 2>&1 ); then
  line=$(grep -E '1 passed' /tmp/golden.log | tail -1)
  if [ -n "$line" ]; then
    echo "ok: $line"
  else
    fail "golden run exited 0 but did not report 1 passed"
    tail -10 /tmp/golden.log | sed 's/^/    /' >&2
  fi
else
  fail "the upstream regression test in /opt/golden did not pass"
  tail -30 /tmp/golden.log | sed 's/^/    /' >&2
fi

# ---------- 2. the project's existing unit test for the git module ----------
echo "== 2. the project's own tests/unit/test_baseline.py =="
if ( cd "$CLI" && "$PY" -m pytest -p no:cacheprovider -q tests/unit/test_baseline.py > /tmp/baseline.log 2>&1 ); then
  line=$(grep -E '[0-9]+ passed' /tmp/baseline.log | tail -1)
  echo "ok: tests/unit/test_baseline.py: ${line:-passed}"
else
  fail "the project's own tests/unit/test_baseline.py did not pass"
  tail -40 /tmp/baseline.log | sed 's/^/    /' >&2
fi

# ---------- 3. authored hidden cases -----------------------------------------
echo "== 3. hidden cases =="
nhidden=0
for f in /tests/hidden/*/*.py; do
  [ -f "$f" ] || continue
  nhidden=$((nhidden + 1))
  cname=$(basename "$(dirname "$f")")
  log="/tmp/hidden-$cname.log"
  if ( cd "$CLI" && "$PY" -m pytest -p no:cacheprovider -q "$f" > "$log" 2>&1 ); then
    line=$(grep -E '[0-9]+ passed' "$log" | tail -1)
    echo "ok: hidden case $cname: ${line:-passed}"
  else
    fail "hidden case $cname"
    tail -40 "$log" | sed 's/^/    /' >&2
  fi
done
if [ "$nhidden" -lt 2 ]; then
  fail "fewer than two hidden cases were exercised (found $nhidden)"
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0