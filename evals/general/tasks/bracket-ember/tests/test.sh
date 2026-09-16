#!/bin/bash
# Verifier for bracket-ember: an upstream-clone debugging task on psf/requests.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# requests.exceptions.JSONDecodeError cannot be round-tripped through pickle
# (the multiple-inheritance MRO makes pickle use IOError's __reduce__, which
# drops the doc/pos constructor arguments). The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, only the
#      minimal tracked source file is modified, and no new files appeared
#      inside the package);
#   1. runs the project's own regression test for this bug, extracted at image
#      build time from the fix commit into /opt/golden/;
#   2. runs the project's own existing self-contained test files, proving the
#      fix broke nothing else;
#   3. runs three authored hidden cases that exercise the same code path from
#      inputs the upstream test does not use: many (msg, doc, pos) payloads
#      across pickle protocols 0..HIGHEST, the full Response.json() path on an
#      invalid response body, and a cross-process round-trip.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=96b22fa18c00831656ee4b286bf1c9062459b00a
FIX_SHA=3ff3ff21dd45957c9e143cd500291959bb15f690
GOLDEN=/opt/golden
PTCFG="$SRC/setup.cfg"

fail () {  # fail LABEL DETAIL...
  echo "FAIL: $1" >&2
  shift
  for line in "$@"; do echo "    $line" >&2; done
  reward=0
}

run_pytest () {  # run_pytest LABEL OUTDIR ARGS...
  label="$1"; out="$2"; shift 2
  if ( "$@" > "$out" 2>&1 ); then
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
  fail "/app/src is not a git clone"
elif [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  fail "/app/src HEAD is not the pinned parent commit" \
       "HEAD=$(git -C "$SRC" rev-parse HEAD 2>/dev/null || echo missing) wanted=$PARENT_SHA"
else
  echo "ok: HEAD is $PARENT_SHA"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  fail "the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)"
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
bad=$(printf '%s\n' "$porcelain" | grep -v '^ M src/requests/exceptions.py$' | grep -v '^?? ' || true)
if [ -n "$bad" ]; then
  fail "unexpected working-tree changes (only src/requests/exceptions.py may be modified):" "$bad"
fi
newpkg=$(printf '%s\n' "$porcelain" | grep '^?? src/requests/' || true)
if [ -n "$newpkg" ]; then
  fail "new files were added inside the requests package:" "$newpkg"
fi
if [ -z "$(git -C "$SRC" diff -- src/requests/exceptions.py 2>/dev/null || true)" ]; then
  fail "the deliverable /app/src is unchanged (no fix was implemented)"
fi

# ---------- 0.5. environment integrity -------------------------------------------
# The python library tree, /opt/golden and /usr/local/bin were fingerprinted at
# image build time. The fingerprints below are literal baselines computed from a
# verified --no-cache build of this exact Dockerfile (the aggregate is
# deterministic across rebuilds; two clean builds matched byte-for-byte). This
# script itself is the pristine host copy that harbor re-uploads before every
# verification, so the baselines cannot be edited from inside the container.
# A tampered interpreter (planted sitecustomize.py, extra .pth, patched stdlib
# or site-packages files, replaced /opt/golden tests, wrapper binaries) shows
# up here as a mismatch and scores 0 even if the deliverable diff looks fine.
echo "== environment integrity =="
aggregate_tree () {  # DIR -> fingerprint of its sorted file-content listing
  ( cd "$1" && find . -type f ! -name '*.pyc' ! -path '*/__pycache__/*' -print0 \
      | sort -z | xargs -0 sha256sum ) | sha256sum | cut -d' ' -f1
}
PYLIB_SHA='8607feeffbf44d9fe93e1d3de32343a94bc44c9756bf93ac3fcd45bda262857a'
GOLDEN_SHA='1487ac2732e0acdf37b1834a64ada99e287b546d33f3538cb568ffcff4706754'
BIN_SHA='fff21440bbfaa08eebfd90e42a274b4b0d244ca04edf32403bf50b682203ece2'

pylib_now=$(aggregate_tree /usr/local/lib/python3.12)
if [ "$pylib_now" != "$PYLIB_SHA" ]; then
  fail "python library tree tampered (site-packages/stdlib differ from the build-time fingerprint; e.g. a planted sitecustomize.py or .pth)" "got=$pylib_now wanted=$PYLIB_SHA"
else
  echo "ok: python library tree matches the build-time fingerprint"
fi
golden_now=$(aggregate_tree /opt/golden)
if [ "$golden_now" != "$GOLDEN_SHA" ]; then
  fail "golden tree tampered (differs from the fix-commit extraction fingerprint)" "got=$golden_now wanted=$GOLDEN_SHA"
else
  echo "ok: golden tree matches the fix-commit extraction fingerprint"
fi
bin_now=$(find /usr/local/bin -type f -exec sha256sum {} + | sort -k2 | sha256sum | cut -d' ' -f1)
if [ "$bin_now" != "$BIN_SHA" ]; then
  fail "/usr/local/bin tampered (wrapper binaries differ from the build-time fingerprint)" "got=$bin_now wanted=$BIN_SHA"
else
  echo "ok: /usr/local/bin matches the build-time fingerprint"
fi

# ---------- 1. golden: the upstream regression test ---------------------------
echo "== golden test (upstream regression test for this bug) =="
if [ ! -s "$GOLDEN/tests/test_requests.py" ]; then
  fail "golden test missing from image"
else
  run_pytest "golden test_json_decode_errors_are_serializable_deserializable" \
    /tmp/golden.out \
    bash -c "cd $GOLDEN && python3 -m pytest tests/test_requests.py::test_json_decode_errors_are_serializable_deserializable -q -p no:cacheprovider" \
    || true
fi

# ---------- 2. the project's own self-contained suite -------------------------
echo "== the project's own existing self-contained tests =="
run_pytest "existing self-contained test files" /tmp/own.out \
  bash -c "cd $SRC && python3 -m pytest -c $PTCFG tests/test_lowlevel.py tests/test_help.py tests/test_hooks.py tests/test_packages.py tests/test_structures.py tests/test_utils.py -k 'not proxy' -q -p no:cacheprovider" \
  || true

# ---------- 3. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  if ( cd "$SRC" && python3 -m pytest -c "$PTCFG" "$case" -q -p no:cacheprovider > "$out" 2>&1 ); then
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