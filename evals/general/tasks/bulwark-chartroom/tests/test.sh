#!/bin/bash
# Verifier for bulwark-chartroom: an upstream-clone debugging task on
# falconry/falcon (issue #2667, fix ce0a35b8fd02747cc72710202886874906b0d47a).
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# Request.root_path returns the WSGI SCRIPT_NAME verbatim (the PEP 3333
# latin-1 tunnel encoding), so a non-ASCII mount prefix is reported as
# mojibake. The verifier:
#   0. checks provenance: HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, the only
#      modified tracked file is falcon/request.py, and no new files appeared
#      inside the falcon/ package or tests/;
#   1. checks module origin under an ISOLATED interpreter (python3 -I -S with
#      an explicit sys.path): falcon and Request.root_path must resolve under
#      /app/src, so a fix implemented outside the deliverable (sitecustomize,
#      .pth hook, pip-installed copy) cannot fake a pass;
#   2. runs the project's own regression test for this bug, extracted at image
#      build time from the fix commit into /opt/golden/ (sha256-pinned in the
#      image and hardcoded below), against the repaired tree - must pass - and
#      against the pristine pre-fix tree at /opt/prefix-src - must FAIL;
#   3. runs the agent's own /app/repro.py against the repaired tree (must
#      exit 0) and against the pristine pre-fix tree (must exit non-zero and
#      still print the observed value: a hardcoded or vacuous reproduction
#      cannot satisfy both directions);
#   4. runs the project's own full test suite on the repaired tree (3786
#      tests), proving the fix broke nothing else;
#   5. runs four authored hidden cases (Cyrillic multi-byte prefix, EUR sign,
#      emoji, and an invalid-UTF-8 byte sequence that forces PEP 3333
#      'replace' semantics) that the upstream test does not cover.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=1ae55f7d46f1f210550972366ee68fc62cd9f3d9
FIX_SHA=ce0a35b8fd02747cc72710202886874906b0d47a
PREFIX=/opt/prefix-src
GOLDEN=/opt/golden/test_root_path_non_ascii_wsgi.py
GOLDEN_SHA256=025496b4c18b7d6bb1395484de5691af3c91cfcabab101d635dc8dcc9648e276   # verified against the image at build time
PTCFG="$SRC/pyproject.toml"

# site-packages used by the default python3; resolved dynamically so the
# isolated launcher below sees the same installed packages pytest would.
SP="$(python3 -c 'import sysconfig; print(sysconfig.get_path("purelib"))' 2>/dev/null || true)"
if [ -z "$SP" ] || [ ! -d "$SP" ] || [ ! -d "$SP/pytest" ]; then
  echo "FAIL: could not resolve the site-packages directory (SP='${SP:-<empty>}')" >&2
  reward=0
fi

# iso_launch LABEL TREE SCRIPT : run a standalone python script with ONLY
# TREE (plus no site) on the import path. Site processing, PYTHONPATH and
# agent-planted wrappers are all invisible to this interpreter.
iso_launch () {
  label="$1"; tree="$2"; script="$3"; shift 3
  if python3 -I -S -c "
import sys
sys.path[:0] = ['$tree']
exec(compile(open('$script', encoding='utf-8').read(), '$script', 'exec'))
" > "/tmp/$label.out" 2>&1; then
    return 0
  fi
  return 1
}

# iso_pytest LABEL TREE OUT ...pytest-args : run pytest with ONLY TREE + the
# resolved site-packages dir on the import path (no site processing).
iso_pytest () {
  label="$1"; tree="$2"; out="$3"; shift 3
  if ( cd "$SRC" \
       && python3 -I -S -c "
import sys
sys.path[:0] = ['$tree', '$SP']
import pytest
raise SystemExit(pytest.main(sys.argv[1:]))
" "$@" -c "$PTCFG" -q -p no:cacheprovider > "$out" 2>&1 ); then
    echo "ok: $label"
    return 0
  fi
  echo "FAIL: $label" >&2
  tail -40 "$out" | sed 's/^/    /' >&2
  reward=0
  return 1
}

# ---------- 0. tree provenance ----------------------------------------------
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
# Tightened (review bulwark-chartroom): the fix commit OBJECT may be absent
# while the fix BYTES are still one command away. A depth-1 `git clone`
# followed by a fetch leaves refs/remotes/origin/master pointing at the
# current master tip, and that tip is a descendant of the fix commit, so
# `git show refs/remotes/origin/master:falcon/request.py` returns the fixed
# file with no network. The clone must therefore hold NO refs at all and
# exactly ONE commit (the pinned parent).
nrefs=$(git -C "$SRC" for-each-ref 2>/dev/null | wc -l)
if [ "$nrefs" -ne 0 ]; then
  echo "FAIL: working clone has $nrefs ref(s); a plain clone left upstream master refs behind, and their tip contains the fix" >&2
  git -C "$SRC" for-each-ref 2>/dev/null | head -5 | sed 's/^/    /' >&2
  reward=0
fi
nall=$(git -C "$SRC" log --all --oneline 2>/dev/null | wc -l)
if [ "$nall" -ne 1 ]; then
  echo "FAIL: working clone object store holds $nall commit(s); it must hold exactly the pinned parent commit" >&2
  reward=0
fi
for ref in $(git -C "$SRC" for-each-ref --format='%(refname)' 2>/dev/null); do
  if git -C "$SRC" show "${ref}:falcon/request.py" 2>/dev/null | grep -q 'isascii'; then
    echo "FAIL: ref $ref contains the fixed falcon/request.py (the answer is readable without network)" >&2
    reward=0
  fi
done
if [ -d /tmp/fixsrc ] || [ -f /tmp/reqattrs_fix.py ]; then
  echo "FAIL: throwaway fix-clone leftovers present in the image (/tmp/fixsrc or /tmp/reqattrs_fix.py); the fix is readable by the agent" >&2
  reward=0
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
bad=$(printf '%s\n' "$porcelain" | grep -v '^ M falcon/request.py$' | grep -v '^?? ' || true)
if [ -n "$bad" ]; then
  echo "FAIL: unexpected working-tree changes (only falcon/request.py may be modified):" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
fi
newpkg=$(printf '%s\n' "$porcelain" | grep -E '^\?\? (falcon|tests)/' || true)
if [ -n "$newpkg" ]; then
  echo "FAIL: new files were added inside the falcon/ package or tests/:" >&2
  printf '%s\n' "$newpkg" | head -10 | sed 's/^/    /' >&2
  reward=0
fi
if [ -z "$(git -C "$SRC" diff -- falcon/request.py 2>/dev/null || true)" ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2
  reward=0
fi

# ---------- 1. module origin: the verdict must measure /app/src ---------------
echo "== module origin (isolated interpreter) =="
if python3 -I -S -c "
import sys, inspect
sys.path[:0] = ['$SRC', '$SP']
import falcon
import falcon.request as fr
af = falcon.__file__
pf = inspect.getsourcefile(fr.Request.root_path.fget)
print('falcon file:', af)
print('root_path property source file:', pf)
assert af.startswith('$SRC/'), af
assert pf is not None and pf.startswith('$SRC/'), pf
" > /tmp/origin.out 2>&1; then
  echo "ok: falcon and Request.root_path both resolve under $SRC"
  sed 's/^/    /' /tmp/origin.out
else
  echo "FAIL: falcon does not resolve to the deliverable under an isolated interpreter:" >&2
  cat /tmp/origin.out | sed 's/^/    /' >&2
  reward=0
fi

# ---------- 2. golden test integrity -----------------------------------------
echo "== golden test integrity =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
elif [ "$(/usr/bin/sha256sum "$GOLDEN" | awk '{print $1}')" != "$GOLDEN_SHA256" ]; then
  echo "FAIL: $GOLDEN does not match the bytes extracted from the upstream fix commit (sha256 expected $GOLDEN_SHA256)" >&2
  reward=0
else
  echo "ok: golden test matches the pinned upstream bytes"
fi
if [ ! -s /opt/pins/pins.sha256 ] || ! ( cd / && sha256sum -c /opt/pins/pins.sha256 > /dev/null 2>&1 ); then
  echo "FAIL: /opt/pins consistency check failed" >&2
  reward=0
fi

# ---------- 3. deliverable /app/repro.py -------------------------------------
echo "== deliverable /app/repro.py =="
if [ ! -s /app/repro.py ]; then
  echo "FAIL: /app/repro.py is missing or empty" >&2
  reward=0
fi
head -1 /app/repro.py >/dev/null 2>&1 && grep -q "falcon" /app/repro.py \
  || { echo "FAIL: /app/repro.py does not reference falcon" >&2; reward=0; }

# ---------- 4. golden test on the REPAIRED tree: must pass --------------------
echo "== golden test on the repaired tree =="
iso_pytest "golden test_root_path_non_ascii_wsgi" "$SRC" /tmp/golden_fixed.out \
  "$GOLDEN" || true

# ---------- 5. golden test on the PRE-FIX tree: must FAIL ---------------------
echo "== golden test on the pristine pre-fix tree (expected failure) =="
if ( cd "$SRC" \
     && python3 -I -S -c "
import sys
sys.path[:0] = ['$PREFIX', '$SP']
import pytest
raise SystemExit(pytest.main(sys.argv[1:]))
" "$GOLDEN" -q -p no:cacheprovider > /tmp/golden_prefix.out 2>&1 ); then
  echo "FAIL: the upstream regression test PASSED on the pristine pre-fix tree (/opt/prefix-src is broken or carries a fix)" >&2
  reward=0
elif grep -q "1 failed" /tmp/golden_prefix.out; then
  echo "ok: golden test fails on the pre-fix tree with the reported symptom"
else
  echo "FAIL: golden test did not fail the expected way on the pre-fix tree" >&2
  tail -15 /tmp/golden_prefix.out | sed 's/^/    /' >&2
  reward=0
fi

# ---------- 6. the agent's OWN reproduction on the REPAIRED tree --------------
echo "== agent reproduction on the repaired tree =="
if iso_launch repro_fixed "$SRC" /app/repro.py; then
  echo "ok: repro exited 0"
  sed 's/^/    /' /tmp/repro_fixed.out | head -5
else
  echo "FAIL: /app/repro.py exited non-zero on the repaired tree" >&2
  head -15 /tmp/repro_fixed.out | sed 's/^/    /' >&2
  reward=0
fi
if ! grep -q "observed root_path:" /tmp/repro_fixed.out; then
  echo "FAIL: repro printed no 'observed root_path:' line on the repaired tree" >&2
  reward=0
fi
if grep -q "^BUG:" /tmp/repro_fixed.out; then
  echo "FAIL: repro still reports the bug on the repaired tree" >&2
  reward=0
fi

# ---------- 7. the agent's OWN reproduction on the PRE-FIX tree: must FAIL ----
echo "== agent reproduction on the pristine pre-fix tree (expected failure) =="
if iso_launch repro_prefix "$PREFIX" /app/repro.py; then
  echo "FAIL: /app/repro.py exited 0 on the pre-fix tree (a hardcoded or vacuous reproduction)" >&2
  head -10 /tmp/repro_prefix.out | sed 's/^/    /' >&2
  reward=0
else
  if grep -q "observed root_path:" /tmp/repro_prefix.out; then
    echo "ok: repro fails on the pre-fix tree and printed the observed value"
  else
    echo "FAIL: repro failed without printing 'observed root_path:' on the pre-fix tree" >&2
    head -10 /tmp/repro_prefix.out | sed 's/^/    /' >&2
    reward=0
  fi
fi

# ---------- 8. hidden cases ---------------------------------------------------
echo "== hidden cases =="
# The four authored cases are enumerated by path, not globbed, so deleting
# or editing one of them cannot silently shrink the hidden set.
hidden_cases=(
  /tests/hidden/cyrillic_prefix/test_root_path_cyrillic_prefix.py
  /tests/hidden/euro_sign/test_root_path_euro_sign.py
  /tests/hidden/multi_byte_emoji/test_root_path_multi_byte_emoji.py
  /tests/hidden/invalid_utf8_bytes/test_root_path_invalid_utf8_bytes.py
)
n_hidden=0
for case in "${hidden_cases[@]}"; do
  if [ ! -f "$case" ]; then
    echo "FAIL: hidden case file missing: $case (deleted or edited?)" >&2
    reward=0
    continue
  fi
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  if ( cd "$SRC" \
       && python3 -I -S -c "
import sys
sys.path[:0] = ['$SRC', '$SP']
import pytest
raise SystemExit(pytest.main(sys.argv[1:]))
" "$case" -q -p no:cacheprovider > "$out" 2>&1 ); then
    echo "ok: hidden case $name"
  else
    echo "FAIL: hidden case $name" >&2
    tail -30 "$out" | sed 's/^/    /' >&2
    reward=0
  fi
done
if [ "$n_hidden" -lt 4 ]; then
  echo "FAIL: fewer than four hidden cases were exercised ($n_hidden/4)" >&2; reward=0
fi

# ---------- 9. the project's OWN full test suite ------------------------------
echo "== the project's full test suite =="
iso_pytest "full suite (tests/)" "$SRC" /tmp/suite.out "$SRC/tests" || true

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0