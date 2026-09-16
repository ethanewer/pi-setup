#!/bin/bash
# Verifier for bracket-bridge: an upstream-clone debugging task on falcon.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# reading the ASGI request's remote address crashes with a TypeError when the
# connection scope's 'client' field is None, where the documented behaviour is
# to fall back to '127.0.0.1' exactly as when the field is missing. The
# verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, only the
#      minimal tracked source file is modified, and no new files appeared
#      inside the falcon package);
#   1. proves harness-owned test fixtures (/opt/golden/* and
#      /tests/hidden/*/test_*.py) are byte-identical to the expected sha256
#      recorded at review time, so rewriting them cannot lighten the gate;
#   2. runs the project's own regression test for this bug, extracted at image
#      build time from the fix commit into /opt/golden/;
#   3. runs the project's own existing ASGI request tests from the tree,
#      proving the fix broke nothing else;
#   4. runs at least two authored hidden cases (a null client combined with
#      proxy headers at the Request level, and an end-to-end request through a
#      real ASGI app with a null client) that the upstream test does not
#      cover;
#   5. FINAL AUTHORITY: runs the isolated source-fidelity probe with
#      `python3 -S` (no site-packages, so no .pth import hook or wrapper can
#      intercept it) and PYTHONPATH=/app/src, so the behavioural verdict comes
#      from the checked-out source itself, not from anything an agent could
#      install or shim. A wrapper that leaves the deliverable buggy scores 0
#      here even if every pytest slice was made to pass.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=bc01a2b0a62415a562430fe590a798c1042ab3f5
FIX_SHA=a54317c7f8ec51a7fec8ce83df6b9f4852113253
GOLDEN=/opt/golden/test_request_asgi.py
PROBE=/opt/golden/probe_isolated.py

# sha256 of the harness-owned fixtures as frozen at review time (2026-09-11).
GOLDEN_SHA=1d643bfbf55667dc2eda7fc0b54b9e59234a55504af21f02d26079eb9aa12112
PROBE_SHA=5592e04b5ba8a9038a88c2b9dd44f5fdd1774bcc81bfd04b5b3d6202b54443aa

run_pytest () {  # run_pytest LABEL OUT ...args
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC" && python3 -m pytest "$@" -q -p no:cacheprovider > "$out" 2>&1 ); then
    echo "ok: $label"
    return 0
  fi
  echo "FAIL: $label" >&2
  tail -40 "$out" | sed 's/^/    /' >&2
  reward=0
  return 1
}

sha256_check () {  # sha256_check LABEL PATH EXPECTED
  local label=$1 path=$2 expected=$3
  local real
  real=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
  if [ "$real" != "$expected" ]; then
    echo "FAIL: $label was modified in place (sha256 expected ${expected}, got ${real:-<missing>})" >&2
    reward=0
    return 1
  fi
  echo "ok: $label sha256 matches"
  return 0
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
bad=$(printf '%s\n' "$porcelain" | grep -v '^ M falcon/asgi/request.py$' | grep -v '^?? ' || true)
if [ -n "$bad" ]; then
  echo "FAIL: unexpected working-tree changes (only falcon/asgi/request.py may be modified):" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
fi
newpkg=$(printf '%s\n' "$porcelain" | grep '^?? falcon/' || true)
if [ -n "$newpkg" ]; then
  echo "FAIL: new files were added inside the falcon package:" >&2
  printf '%s\n' "$newpkg" | head -5 | sed 's/^/    /' >&2
  reward=0
fi
if [ -z "$(git -C "$SRC" diff -- falcon/asgi/request.py 2>/dev/null || true)" ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2
  reward=0
fi

# ---------- 1. harness-owned fixture integrity ---------------------------------
echo "== harness-owned fixture integrity =="
sha256_check "golden regression test" "$GOLDEN" "$GOLDEN_SHA" || true
sha256_check "isolated probe" "$PROBE" "$PROBE_SHA" || true

hidden_ok=1
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  nfiles=0
  for f in "$case"*; do
    b=$(basename "$f")
    [ "$b" = "__pycache__" ] && continue
    nfiles=$((nfiles + 1))
    case "$name" in
      case-null-client-headers) want="test_null_client_headers.py";;
      case-app-endtoend) want="test_app_endtoend.py";;
      *) want="<none>";;
    esac
    if [ "$b" != "$want" ]; then
      echo "FAIL: hidden case $name contains unexpected file '$b'" >&2
      reward=0; hidden_ok=0
    fi
    if [ "$name" = "case-null-client-headers" ]; then
      sha256_check "hidden case $name/$b" "$f" "29cf909805d1efed3618f1dfb096f948eb7b3443a98a4f01d5cf30b835f451e4" || hidden_ok=0
    elif [ "$name" = "case-app-endtoend" ]; then
      sha256_check "hidden case $name/$b" "$f" "4efc903d84c25371711d85357cf0ea99d460b903d93cddce237edca0ca3202e7" || hidden_ok=0
    fi
  done
  if [ "$nfiles" -ne 1 ]; then
    echo "FAIL: hidden case $name should contain exactly one test file" >&2
    reward=0; hidden_ok=0
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases remain" >&2
  reward=0; hidden_ok=0
fi
if [ "$hidden_ok" -eq 0 ]; then
  echo "FAIL: harness-owned hidden fixtures were not left byte-identical" >&2
fi

# ---------- 2. golden: the upstream regression test ---------------------------
echo "== golden test (upstream regression test for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
else
  run_pytest "golden test_client_none_in_scope" /tmp/golden.out "$GOLDEN::test_client_none_in_scope" \
    || true
fi

# ---------- 3. the project's own existing ASGI request tests -----------------
echo "== the project's own existing ASGI request tests =="
run_pytest "existing tests/asgi/test_request_asgi.py" /tmp/own-req.out tests/asgi/test_request_asgi.py \
  || true
run_pytest "existing tests/asgi/test_request_context_asgi.py" /tmp/own-ctx.out tests/asgi/test_request_context_asgi.py \
  || true
run_pytest "existing tests/asgi/test_misc.py" /tmp/own-misc.out tests/asgi/test_misc.py \
  || true

# ---------- 4. hidden cases ---------------------------------------------------
echo "== hidden cases =="
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  if ( cd "$SRC" && python3 -m pytest "$case" -q -p no:cacheprovider > "$out" 2>&1 ); then
    echo "ok: hidden case $name"
  else
    echo "FAIL: hidden case $name" >&2
    tail -40 "$out" | sed 's/^/    /' >&2
    reward=0
  fi
done

# ---------- 5. isolated source-fidelity probe (final authority) ----------------
echo "== isolated source-fidelity probe =="
if [ ! -s "$PROBE" ]; then
  echo "FAIL: isolated probe missing from image" >&2; reward=0
elif ( cd "$SRC" && PYTHONPATH="$SRC" python3 -S "$PROBE" > /tmp/probe.out 2>&1 ); then
  echo "ok: probe passed against the checked-out source"
  tail -5 /tmp/probe.out | sed 's/^/    /'
else
  echo "FAIL: isolated probe did not pass against the checked-out source (a wrapper around the buggy tree cannot score 1)" >&2
  tail -25 /tmp/probe.out | sed 's/^/    /' >&2
  reward=0
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0