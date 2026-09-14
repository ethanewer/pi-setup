#!/bin/bash
# Verifier for yard-sloop: an upstream-clone debugging task on semgrep.
#
# Semgrep drops the `_git` path segment from Azure DevOps project URLs
# (issue semgrep/semgrep#10184): get_url_from_sstp_url rebuilds
# ".../_git/Core.Thing" as ".../Core.Thing", so finding links 404. The agent
# must (a) author /app/reproduce.py following the contract in the instruction
# (prints "url=<computed>" for the canonical Azure remote, exits 0 iff the
# result keeps the /_git segment), (b) repair the tree at /app/src, and (c)
# reconcile the project's own tracked regression test (which encoded the
# buggy expectation) so the project's own suite is green.
#
# Verifier sections:
#   0. tree provenance: HEAD pinned at the parent, fix commit unreachable,
#      import resolves to the editable /app/src tree, only the two source
#      files + the one tracked test file modified, no smuggled untracked
#      files (cache dirs exempt), /opt/golden and the pristine pre-fix
#      sources byte-identical to their build-time hashes (the trial runs as
#      root and could otherwise rewrite them);
#   1. the agent's own reproduction, run in TWO contexts and cross-checked
#      against an independent control computation in the same context:
#      pre-fix (PYTHONPATH to /opt/pristine/cli/src) must exit nonzero and
#      print the BUGGY url; repaired (editable install) must exit 0 and
#      print the CORRECT url;
#   2. the project's own regression test, run from the agent's tree;
#   3. the same regression test from the sha-guarded authoritative copy
#      (/opt/golden, extracted from the upstream fix at build time);
#   4. the whole package compiles and the touched modules import cleanly;
#   5. at least two authored hidden cases over inputs the upstream test does
#      not use.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=e3f9cc50988fb04241c1626e427246538c425314
FIX_SHA=d7a3e3bd43c77edceeff6e8fa5068005d029dac8
GOLDEN=/opt/golden/test_meta.py
# sha256 of /opt/golden/test_meta.py as extracted from the fix commit at
# image build time; re-checked here because the trial may run as root.
GOLDEN_SHA256=6f77c1745e72dd6ec57c9d0ef6a74875b32ea7816c1e0b59e465448b37bfede0
# sha256 of the two pristine pre-fix source files; re-checked because a root
# trial could edit /opt/pristine to fake the pre-fix context.
PRISTINE_PARSER_SHA=181d41ebf4c17a4ba001899ff2993f699bd498f84b5da7ae8d31588510daef6c
PRISTINE_META_SHA=3c36c7755bf05fc97b718eb6987bb664770897344cb6c68b6f1d5063f015566a
REPRO=/app/reproduce.py
REMOTE='https://test@dev.azure.com/test/TestName/_git/Core.Thing'
URL_FIXED='https://dev.azure.com/test/TestName/_git/Core.Thing'
URL_BUGGY='https://dev.azure.com/test/TestName/Core.Thing'

# control computation: what the imported library actually produces
control_url () {  # control_url PYTHONPATH_EXTRA
  if [ -n "${1:-}" ]; then
    ( cd /tmp && PYTHONPATH="$1" python3 -c "from semgrep.meta import get_url_from_sstp_url; print(get_url_from_sstp_url('$REMOTE'))" )
  else
    ( cd /tmp && env -u PYTHONPATH python3 -c "from semgrep.meta import get_url_from_sstp_url; print(get_url_from_sstp_url('$REMOTE'))" )
  fi
}

run_pytest () {  # run_pytest LABEL OUT ...args (runs inside "$SRC")
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

if ! python3 -c 'import semgrep; assert semgrep.__file__.startswith("/app/src/"), semgrep.__file__' 2>/dev/null; then
  echo "FAIL: import semgrep does not resolve to the editable checkout at /app/src (package was replaced?)" >&2
  python3 -c 'import semgrep; print("    semgrep imported from:", semgrep.__file__)' 2>&1 | head -2 >&2
  reward=0
fi

if [ "$(sha256sum "/opt/pristine/cli/src/semgrep/external/git_url_parser.py" 2>/dev/null | cut -d' ' -f1)" != "$PRISTINE_PARSER_SHA" ]; then
  echo "FAIL: /opt/pristine pre-fix parser was modified — the pre-fix context is not trustworthy" >&2; reward=0
fi
if [ "$(sha256sum "/opt/pristine/cli/src/semgrep/meta.py" 2>/dev/null | cut -d' ' -f1)" != "$PRISTINE_META_SHA" ]; then
  echo "FAIL: /opt/pristine pre-fix meta.py was modified — the pre-fix context is not trustworthy" >&2; reward=0
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
bad=$(printf '%s\n' "$porcelain" | grep -v '^?? ' \
  | grep -Fv ' M cli/src/semgrep/external/git_url_parser.py' \
  | grep -Fv ' M cli/src/semgrep/meta.py' \
  | grep -Fv ' M cli/tests/default/e2e-pro/test_meta.py' \
  | grep -v '^$' || true)
if [ -n "$bad" ]; then
  echo "FAIL: unexpected tracked working-tree changes (only the two source files and the tracked regression test may be modified):" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
fi
untracked=$(printf '%s\n' "$porcelain" | grep '^?? ' || true)
bad_untracked=$(printf '%s\n' "$untracked" | grep -v '__pycache__' | grep -v '\.pyc$' | grep -v '\.pytest_cache' | grep -v 'egg-info' || true)
if [ -n "$bad_untracked" ]; then
  echo "FAIL: unexpected new files inside the repository (cache dirs are exempt):" >&2
  printf '%s\n' "$bad_untracked" | head -10 | sed 's/^/    /' >&2
  reward=0
fi
if [ -z "$(git -C "$SRC" diff -- cli/src/semgrep/external/git_url_parser.py cli/src/semgrep/meta.py 2>/dev/null || true)" ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no source fix was implemented)" >&2
  reward=0
fi

# Harness-owned dirs are re-uploaded pristine before this runs, and the
# image's /opt/golden is hash-guarded, but sweep any conftest.py the agent
# may have dropped so no collection-time shim is picked up by pytest.
find /opt/golden /tests "$SRC" -name 'conftest.py' -delete 2>/dev/null || true

# ---------- 1. the agent's own reproduction, both contexts -------------------
echo "== the agent's reproduction, pre-fix and repaired contexts =="
if [ ! -f "$REPRO" ]; then
  echo "FAIL: deliverable $REPRO does not exist" >&2; reward=0
else
  if [ "$(sha256sum "$GOLDEN" 2>/dev/null | cut -d' ' -f1)" != "$GOLDEN_SHA256" ]; then
    echo "FAIL: /opt/golden/test_meta.py does not match the upstream fix-commit extraction (was it replaced?)" >&2
    reward=0
  fi

  # control URLs in both contexts (what the imported library truly produces)
  ctl_pre=$(control_url "/opt/pristine/cli/src")
  ctl_rep=$(control_url '')
  if [ "$ctl_pre" != "$URL_BUGGY" ]; then
    echo "FAIL: pre-fix control computed '$ctl_pre', expected '$URL_BUGGY' (pristine context unusable)" >&2; reward=0
  fi
  if [ "$ctl_rep" != "$URL_FIXED" ]; then
    echo "FAIL: repaired control computed '$ctl_rep', expected '$URL_FIXED' (repair not in effect)" >&2; reward=0
  fi

  # pre-fix context: must FAIL and print exactly the buggy url the control sees
  if ( cd /tmp && PYTHONPATH=/opt/pristine/cli/src python3 "$REPRO" > /tmp/repro-prefix.out 2>&1 ); then
    echo "FAIL: the reproduction exited 0 in the PRE-FIX context — it does not demonstrate the bug" >&2
    reward=0
  else
    pref_rc=$?
  fi
  pre_url=$(grep -m1 '^url=' /tmp/repro-prefix.out || true)
  if [ "$pre_url" != "url=$ctl_pre" ]; then
    echo "FAIL: in the PRE-FIX context the reproduction printed '$pre_url' but the control computes 'url=$ctl_pre' (hardcoded or computed from the wrong tree)" >&2
    cat /tmp/repro-prefix.out | sed 's/^/    /' >&2
    reward=0
  else
    echo "ok: pre-fix context: reproduction exits nonzero and prints the buggy url ($pre_url)"
  fi

  # repaired context: must exit 0 and print the url the repaired library computes
  if ( cd /tmp && env -u PYTHONPATH python3 "$REPRO" > /tmp/repro-repaired.out 2>&1 ); then
    :
  else
    rc=$?
    echo "FAIL: the reproduction exited $rc in the repaired context; expected 0 (once the tree is fixed, the reproduction must pass)" >&2
    tail -5 /tmp/repro-repaired.out | sed 's/^/    /' >&2
    reward=0
  fi
  rep_url=$(grep -m1 '^url=' /tmp/repro-repaired.out || true)
  if [ "$rep_url" != "url=$ctl_rep" ]; then
    echo "FAIL: in the repaired context the reproduction printed '$rep_url' but the repaired library itself computes 'url=$ctl_rep' (hardcoded or wrapped?)" >&2
    cat /tmp/repro-repaired.out | sed 's/^/    /' >&2
    reward=0
  else
    echo "ok: repaired context: reproduction printed $rep_url, matching the repaired library"
  fi
fi

# ---------- 2. the project's own regression test, from the agent's tree ------
echo "== the project's own regression test (from the agent's tree) =="
run_pytest "tracked regression test cli/tests/default/e2e-pro/test_meta.py" \
  /tmp/tree-test.out cli/tests/default/e2e-pro/test_meta.py || true

# ---------- 2.5 the project's own existing pure-python unit suite -------------
echo "== the project's own existing unit tests (proves nothing else broke) =="
run_pytest "unit test_clean_project_url.py" /tmp/unit-clean.out cli/tests/default/unit/test_clean_project_url.py || true
run_pytest "unit test_bytesize.py" /tmp/unit-bytesize.out cli/tests/default/unit/test_bytesize.py || true
run_pytest "unit test_semver_matching.py" /tmp/unit-semver.out cli/tests/default/unit/test_semver_matching.py || true

# ---------- 3. the authoritative fixed-era regression test --------------------
echo "== the authoritative fixed-era regression test (/opt/golden) =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test file missing from image" >&2; reward=0
elif [ "$(sha256sum "$GOLDEN" | cut -d' ' -f1)" != "$GOLDEN_SHA256" ]; then
  echo "FAIL: /opt/golden/test_meta.py does not match the upstream fix-commit extraction (was it replaced?)" >&2
  reward=0
else
  run_pytest "golden test_meta.py::test_git_url_parser" /tmp/golden.out \
    "$GOLDEN::test_git_url_parser" || true
fi

# ---------- 4. whole package compiles and imports -----------------------------
echo "== package integrity =="
if python3 -m compileall -q "$SRC/cli/src/semgrep" > /tmp/compileall.out 2>&1; then
  echo "ok: cli/src/semgrep compiles"
else
  echo "FAIL: the semgrep package does not compile" >&2
  tail -30 /tmp/compileall.out | sed 's/^/    /' >&2
  reward=0
fi
if ( cd /tmp && env -u PYTHONPATH python3 -c 'import semgrep.meta, semgrep.external.git_url_parser, semgrep.git, semgrep.state' 2>/tmp/imports.out ); then
  echo "ok: touched modules import cleanly"
else
  echo "FAIL: a touched module no longer imports" >&2
  tail -30 /tmp/imports.out | sed 's/^/    /' >&2
  reward=0
fi

# ---------- 5. hidden cases ---------------------------------------------------
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