#!/bin/bash
# Verifier for skiff-beacon: an upstream-clone debugging task on falcon.
#
# The agent must write its own reproduction (/app/repro.py) of a real
# upstream bug and fix it in the real checkout at /app/src: with
# unquote_plus=False the accelerated uri.decode() misreads a literal '+'
# followed by two hex digits as a percent escape (decode('+00') -> '\x00',
# NUL injected into ISO-8601 timestamp path segments). The verifier:
#   0. checks provenance: /app/src is still the pinned parent commit, the
#      upstream fix commit is unreachable from the clone, the only tracked
#      file differing from the pin is the source file the fix requires
#      (build artifacts are untracked), and /app/repro.py exists;
#   1. verifies the pristine pre-fix tree at /opt/pristine still exhibits
#      the bug (integrity smoke), so the pre-fix run below is meaningful;
#   2. rebuilds the compiled extension from the repaired tree (touch +
#      setup.py build_ext --inplace, ~2 s) so the binaries reflect the
#      source actually in the tree;
#   3. runs the project's own regression test for this behaviour — the
#      fixed test_utils.py extracted from the upstream fix commit into
#      /opt/golden (sha256-checked) — and requires the parametrized
#      uri_decode_unquote_plus selection to pass;
#   4. runs the project's own suite slice (test_utils.py, test_query_params.py,
#      test_cython.py) against the repaired tree: nothing else broke;
#   5. runs the agent's /app/repro.py twice, against the pristine pre-fix
#      tree via PYTHONPATH (must fail there) and against the repaired tree
#      (must pass), proving the reproduction genuinely detects the defect;
#   6. runs two authored hidden cases (hex-adjacency and offset timestamps)
#      against the repaired tree.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PRISTINE=/opt/pristine
GOLDEN=/opt/golden/test_utils.py
REPRO=/app/repro.py
PARENT_SHA=6566f4a4254fcc0158635c2e3bd4983663070ae4
FIX_SHA=7f55a5eb2e10b96d83ecc57384d4c8dca8bc4221
GOLDEN_SHA256=01737d5e7cc255d8690b454cf81173c18b8b2890a80449593b940845de19193b

fail() {  # fail MESSAGE
  echo "FAIL: $1" >&2
  reward=0
}

ok() { echo "ok: $1"; }

# ---------- 0. deliverables and harness assets --------------------------------
echo "== deliverables and harness assets =="
if [ -f "$REPRO" ] && [ -r "$REPRO" ]; then
  ok "/app/repro.py present"
else
  fail "/app/repro.py is missing or unreadable (deliverable)"
fi

if python3 -c "import ast,sys; ast.parse(open('$REPRO').read())" 2>/dev/null; then
  ok "/app/repro.py parses as Python"
else
  fail "/app/repro.py is not valid Python"
fi

golden_sha=$(sha256sum "$GOLDEN" 2>/dev/null | cut -d' ' -f1)
if [ "$golden_sha" = "$GOLDEN_SHA256" ]; then
  ok "golden test file sha256 matches the upstream fix commit"
else
  fail "golden test file missing or altered (${golden_sha:-none})"
fi

if [ -d "$PRISTINE/.git" ]; then
  ok "/opt/pristine present"
else
  fail "/opt/pristine missing"
fi

# ---------- 1. tree provenance ------------------------------------------------
echo "== tree provenance =="
if [ ! -d "$SRC/.git" ]; then
  fail "/app/src is not a git clone"
elif [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  fail "/app/src HEAD is not the pinned parent commit"
else
  ok "HEAD is the pinned parent commit"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  fail "the upstream fix commit is reachable from the working clone"
else
  ok "the upstream fix commit object is absent from the clone"
fi

if git -C "$SRC" diff --quiet --exit-code -- falcon/cyutil/uri.pyx 2>/dev/null; then
  fail "the source file the fix requires is unchanged from the pinned commit"
else
  ok "the source file the fix requires differs from the pinned commit"
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
provenance_bad=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  st=${line:0:2}
  path=${line:3}
  case "$st" in
    ' M'|'M '|'MM')
      if [ "$path" = "falcon/cyutil/uri.pyx" ]; then
        ok_tracked=1
      else
        echo "FAIL: unexpected tracked modification: $line" >&2
        provenance_bad=1
      fi
      ;;
    'D '|' D'|'AD'|'MD'|'DM')
      echo "FAIL: a tracked file was deleted or renamed: $line" >&2
      provenance_bad=1
      ;;
    '??')
      case "$path" in
        falcon/cyutil/uri.c|falcon/cyutil/reader.c|falcon/cyutil/misc.c) ;;
        falcon/cyutil/*.so) ;;
        build/*) ;;
        .pytest_cache/*) ;;
        */__pycache__/*) ;;
        __pycache__/*) ;;
        falcon.egg-info/*) ;;
        *) echo "FAIL: unexpected untracked file: $line" >&2; provenance_bad=1 ;;
      esac
      ;;
    *)
      echo "FAIL: unexpected status line: $line" >&2
      provenance_bad=1
      ;;
  esac
done <<< "$porcelain"
if [ "$provenance_bad" = 1 ]; then
  fail "working tree differs from the pinned commit in more than the fix"
else
  ok "working tree differs from the pinned commit only in the fix (plus build artifacts)"
fi

# ---------- 2. pristine pre-fix tree still exhibits the bug -------------------
echo "== pristine pre-fix tree integrity =="
if [ "$(git -C "$PRISTINE" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  fail "/opt/pristine is not at the parent commit"
else
  ok "/opt/pristine is at the parent commit"
fi

if [ -n "$(git -C "$PRISTINE" diff --name-only 2>/dev/null || true)" ]; then
  fail "/opt/pristine has tracked modifications"
else
  ok "/opt/pristine has no tracked modifications"
fi

if (cd /tmp && timeout 60 env PYTHONPATH="$PRISTINE" python3 -c \
    "from falcon.cyutil.uri import decode; \
     assert decode('+00', unquote_plus=False) != '+00'" 2>/dev/null); then
  ok "pristine pre-fix tree exhibits the defect"
else
  fail "pristine pre-fix tree no longer exhibits the defect (smoke failed)"
fi

# ---------- 3. rebuild the extension from the repaired tree -------------------
echo "== rebuild compiled extension from the repaired tree =="
# touch forces cythonize to regenerate the C source and gcc to recompile, so a
# hand-placed .so or a stale object cannot survive the check.
if touch "$SRC/falcon/cyutil/uri.pyx" \
   && ( cd "$SRC" && python3 setup.py build_ext --inplace \
        > /tmp/rebuild.log 2>&1 ); then
  ok "in-place extension rebuild succeeded"
else
  fail "in-place extension rebuild failed"
  tail -20 /tmp/rebuild.log | sed 's/^/    /' >&2 || true
fi

# ---------- 4. project's own regression test (golden) -------------------------
echo "== upstream regression test on the repaired tree =="
if [ "$reward" = 1 ]; then
  out=$(cd "$SRC" && PYTHONPATH="$SRC" timeout 180 python3 -m pytest -q \
        "$GOLDEN" -k uri_decode_unquote_plus 2>&1); rc=$?
  if [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q "2 passed"; then
    ok "test_uri_decode_unquote_plus: 2 parametrized variants pass"
  else
    fail "the upstream regression selection did not pass"
    printf '%s\n' "$out" | tail -15 | sed 's/^/    /' >&2 || true
  fi
fi

# ---------- 5. the project's own suite slice ----------------------------------
echo "== project's own suite slice on the repaired tree =="
for tf in tests/test_utils.py tests/test_query_params.py tests/test_cython.py; do
  if [ "$reward" = 1 ]; then
    out=$(cd "$SRC" && PYTHONPATH="$SRC" timeout 300 python3 -m pytest -q \
          "$tf" 2>&1); rc=$?
    if [ "$rc" = 0 ]; then
      ok "$tf: $(printf '%s\n' "$out" | tail -1)"
    else
      fail "$tf did not pass on the repaired tree"
      printf '%s\n' "$out" | tail -15 | sed 's/^/    /' >&2 || true
    fi
  fi
done

# ---------- 6. the agent's reproduction, both directions ----------------------
echo "== agent reproduction against the pre-fix tree (must fail) =="
if [ "$reward" = 1 ]; then
  out=$(cd /tmp && timeout 120 env PYTHONPATH="$PRISTINE" python3 "$REPRO" 2>&1); rc=$?
  if [ "$rc" != 0 ]; then
    ok "/app/repro.py fails on the pristine pre-fix tree (rc=$rc), reproducing the defect"
  else
    fail "/app/repro.py exited 0 on the pristine pre-fix tree: it does not detect the defect"
    printf '%s\n' "$out" | tail -15 | sed 's/^/    /' >&2 || true
  fi
fi

echo "== agent reproduction against the repaired tree (must pass) =="
if [ "$reward" = 1 ]; then
  out=$(cd /tmp && timeout 120 env PYTHONPATH="$SRC" python3 "$REPRO" 2>&1); rc=$?
  if [ "$rc" = 0 ]; then
    ok "/app/repro.py passes on the repaired tree"
  else
    fail "/app/repro.py failed on the repaired tree (rc=$rc)"
    printf '%s\n' "$out" | tail -15 | sed 's/^/    /' >&2 || true
  fi
fi

# ---------- 7. authored hidden cases ------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  chk="$case/check.py"
  [ -f "$chk" ] || continue
  n_hidden=$((n_hidden + 1))
  cname=$(basename "$case")
  if [ "$reward" = 1 ]; then
    out=$(cd /tmp && timeout 300 env PYTHONPATH="$SRC" python3 "$chk" 2>&1); rc=$?
    if [ "$rc" = 0 ]; then
      ok "hidden case $cname: $(printf '%s\n' "$out" | tail -1)"
    else
      fail "hidden case $cname"
      printf '%s\n' "$out" | tail -15 | sed 's/^/    /' >&2 || true
    fi
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  fail "fewer than two hidden cases were exercised"
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0