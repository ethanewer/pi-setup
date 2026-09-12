#!/bin/bash
# Verifier for bracket-anchor: an upstream-clone debugging task on aiohttp.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# the RFC 6265 expiry-date parser accepts non-ASCII decimal digits.  The
# verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, only the
#      minimal tracked source file is modified, and no new files appeared
#      inside the package);
#   1. runs the project's own regression test for this bug, extracted at image
#      build time from the fix commit into /opt/golden/;
#   2. runs the project's own existing cookie-jar test file from the tree,
#      proving the fix broke nothing else;
#   3. runs at least three authored hidden cases (other digit scripts at the
#      parser level, end-to-end cookie-expiry semantics, and ASCII-format
#      regression guards) that the upstream test does not cover.
#
# Review hardening (v43 review of bracket-anchor):
#   * /opt/golden/test_cookiejar.py is digest-checked against the SHA-256 of
#     the file as extracted from the upstream FIX commit at image build time,
#     so rewriting the in-image golden file is not a way to earn reward 1.
#   * Every suite runs through an isolated interpreter (python3 -I -S with
#     explicit sys.path of /app/src plus the resolved site-packages dir).  An
#     agent-side "wrapper" planted in the image (sitecustomize.py, .pth hooks,
#     or replaced functions in site-packages) is therefore invisible to the
#     verdict: with -S the site module never runs, so sitecustomize and .pth
#     processing are skipped, and aiohttp is imported straight from /app/src.
#   * A module-origin check asserts that aiohttp itself and the callable
#     CookieJar._parse_date both resolve to files under /app/src, so a fix
#     implemented outside the deliverable (e.g. by replacing the function
#     through an import hook) cannot fake a pass.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=58bae08b7e4831c6c184fe22233bfc19941c700b
FIX_SHA=d5d068cb541ab7df5ecca14515475f9d4a379c5e
GOLDEN=/opt/golden/test_cookiejar.py
GOLDEN_SHA256=f4512c993dcdb2b0913da7fa00b1a63c0bfb272972e9b873464b01028a04e2ad
PTCFG="$SRC/setup.cfg"

# site-packages used by the default python3; resolved dynamically so the
# isolated launcher below sees the same installed packages pytest would.
SP="$(python3 -c 'import sysconfig; print(sysconfig.get_path("purelib"))' 2>/dev/null || true)"
if [ -z "$SP" ] || [ ! -d "$SP" ] || [ ! -d "$SP/pytest" ]; then
  echo "FAIL: could not resolve the site-packages directory (SP='${SP:-<empty>}')" >&2
  reward=0
fi

iso_pytest () {  # iso_pytest LABEL OUT ...args   (pytest argv)
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC" \
       && python3 -I -S -c "
import sys
sys.path[:0] = ['$SRC', '$SP']
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
bad=$(printf '%s\n' "$porcelain" | grep -v '^ M aiohttp/cookiejar.py$' | grep -v '^?? ' || true)
if [ -n "$bad" ]; then
  echo "FAIL: unexpected working-tree changes (only aiohttp/cookiejar.py may be modified):" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
fi
newpkg=$(printf '%s\n' "$porcelain" | grep '^?? aiohttp/' || true)
if [ -n "$newpkg" ]; then
  echo "FAIL: new files were added inside the aiohttp package:" >&2
  printf '%s\n' "$newpkg" | head -5 | sed 's/^/    /' >&2
  reward=0
fi
if [ -z "$(git -C "$SRC" diff -- aiohttp/cookiejar.py 2>/dev/null || true)" ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2
  reward=0
fi

# ---------- 0.5 module-origin: the verdict must measure /app/src --------------
echo "== module origin (isolated interpreter) =="
if python3 -I -S -c "
import sys, inspect
sys.path[:0] = ['$SRC', '$SP']
import aiohttp
import aiohttp.cookiejar as cj
af = aiohttp.__file__
cf = inspect.getsourcefile(cj.CookieJar._parse_date)
print('aiohttp file:', af)
print('_parse_date source file:', cf)
assert af.startswith('$SRC/'), af
assert cf is not None and cf.startswith('$SRC/'), cf
" > /tmp/origin.out 2>&1; then
  echo "ok: aiohttp and CookieJar._parse_date both resolve under $SRC"
  sed 's/^/    /' /tmp/origin.out
else
  echo "FAIL: aiohttp does not resolve to the deliverable under an isolated interpreter:" >&2
  cat /tmp/origin.out | sed 's/^/    /' >&2
  reward=0
fi

# ---------- 1. golden: the upstream regression test ---------------------------
echo "== golden test (upstream regression test for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
elif [ "$(/usr/bin/sha256sum "$GOLDEN" | awk '{print $1}')" != "$GOLDEN_SHA256" ]; then
  echo "FAIL: /opt/golden/test_cookiejar.py does not match the bytes extracted from the upstream fix commit (sha256 expected $GOLDEN_SHA256)" >&2
  reward=0
else
  iso_pytest "golden test_date_parsing" /tmp/golden.out "$GOLDEN::test_date_parsing" \
    || true
fi

# ---------- 2. the project's own existing cookie-jar suite --------------------
echo "== the project's own existing cookie-jar tests =="
iso_pytest "existing tests/test_cookiejar.py" /tmp/own.out tests/test_cookiejar.py \
  || true

# ---------- 3. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  if ( cd "$SRC" \
       && python3 -I -S -c "
import sys
sys.path[:0] = ['$SRC', '$SP']
import pytest
raise SystemExit(pytest.main(sys.argv[1:]))
" "$case" -c "$PTCFG" -q -p no:cacheprovider > "$out" 2>&1 ); then
    echo "ok: hidden case $name"
  else
    echo "FAIL: hidden case $name" >&2
    tail -40 "$out" | sed 's/^/    /' >&2
    reward=0
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases were exercised" >&2; reward=0
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0