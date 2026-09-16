#!/bin/bash
# Verifier for cistern-crest: an upstream-clone debugging task on gallery-dl.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# the --mtime postprocessor leaks a previous file's timestamp onto files with
# no usable date metadata and turns the 'no date' sentinel into an absurd
# year-0001 timestamp.  The verifier:
#   0. restores the build-time sitecustomize.py from a host-uploaded pristine
#      copy (/tests/sitecustomize.pristine.py), so runtime behaviour is always
#      measured against the deliverable tree and not against startup hooks
#      (sitecustomize/.pth/...) an agent could plant in site-packages;
#   1. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, only the
#      minimal tracked source file is modified, and no new files appeared
#      inside the package);
#   2. asserts the buggy early return ('if mtime is None: return') is gone
#      from gallery_dl/postprocessor/mtime.py: behavioural tests alone cannot
#      separate a fixed tree from a runtime wrapper over the buggy tree;
#   3. runs the project's own regression tests for this bug, extracted at
#      image build time from the fix commit into /opt/golden/;
#   4. runs the project's own existing postprocessor tests (excluding the
#      mtime tests, whose in-tree expectations encode the bug), proving the
#      fix broke nothing else;
#   5. runs authored hidden cases (a several-files-one-job stale-metadata
#      sequence and the value/key option paths with missing, empty and
#      invalid inputs) that the upstream tests do not cover.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=a879e5d468e43fac9daf6bdc4726f853a9c85567
FIX_SHA=12e2113a80eb4bf557dff4aba6e1775d74d8afc0
GOLDEN=/opt/golden/test_postprocessor.py
GOLDEN_SHA256=075d4c91a5402850be04f0118285666583bfae100dc2e8e715f9d66879f26fab

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

# ---------- 0. harness plumbing restore ---------------------------------------
# The agent runs as root in the same filesystem the verifier later uses, so it
# could edit /usr/local/lib/python3.12/site-packages/sitecustomize.py (or plant
# other import hooks) to change behaviour without touching the checkout.  /tests
# is re-uploaded from the host at verify time, so the pristine copy of the
# build-time sitecustomize.py shipped beside this script is trustworthy:
# restore it before any pytest run.
echo "== harness plumbing restore =="
PRISTINE=/tests/sitecustomize.pristine.py
if [ ! -s "$PRISTINE" ]; then
  echo "FAIL: pristine sitecustomize copy missing from /tests" >&2
  reward=0
elif ! cp "$PRISTINE" /usr/local/lib/python3.12/site-packages/sitecustomize.py; then
  echo "FAIL: could not restore sitecustomize.py from the pristine copy" >&2
  reward=0
else
  echo "ok: restored sitecustomize.py from the host-uploaded pristine copy"
fi

# ---------- 1. tree provenance -----------------------------------------------
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
bad=$(printf '%s\n' "$porcelain" | grep -v '^ M gallery_dl/postprocessor/mtime.py$' | grep -v '^?? ' || true)
if [ -n "$bad" ]; then
  echo "FAIL: unexpected working-tree changes (only gallery_dl/postprocessor/mtime.py may be modified):" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
fi
newpkg=$(printf '%s\n' "$porcelain" | grep '^?? gallery_dl/' || true)
if [ -n "$newpkg" ]; then
  echo "FAIL: new files were added inside the gallery_dl package:" >&2
  printf '%s\n' "$newpkg" | head -5 | sed 's/^/    /' >&2
  reward=0
fi
if [ -z "$(git -C "$SRC" diff -- gallery_dl/postprocessor/mtime.py 2>/dev/null || true)" ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2
  reward=0
fi

# ---------- 2. the fix must live in the deliverable source --------------------
# Behavioural checks alone cannot distinguish a fixed tree from a runtime
# wrapper over the buggy tree (sitecustomize/.pth/poisoned __pycache__).  The
# bug is the early return in run(): a real fix cannot leave this exact
# construct in the deliverable file.
echo "== the fix must be in the deliverable source =="
if python3 - "$SRC/gallery_dl/postprocessor/mtime.py" <<'PY'
import re
import sys

src = open(sys.argv[1]).read()
m = re.search(r"if\s+mtime\s+is\s+None\s*:\s*\n\s*return\b", src)
sys.exit(0 if m else 1)
PY
then
  echo "FAIL: the buggy early return ('if mtime is None: return') is still present in the deliverable gallery_dl/postprocessor/mtime.py -- the observable behaviour must come from a real fix in the tree, not from a runtime wrapper" >&2
  reward=0
else
  echo "ok: no buggy early-return construct in the deliverable source"
fi

# ---------- 3. golden: the upstream regression tests ---------------------------
echo "== golden test (upstream regression tests for this bug) ="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
elif [ "$(sha256sum "$GOLDEN" | cut -d' ' -f1)" != "$GOLDEN_SHA256" ]; then
  echo "FAIL: golden test file was modified (tampered with)" >&2; reward=0
else
  echo "ok: golden file hash matches the build-time extraction"
  run_pytest "golden MtimeTest" /tmp/golden.out "$GOLDEN::MtimeTest" \
    || true
fi

# ---------- 4. the project's own existing postprocessor suite -----------------
echo "== the project's own existing postprocessor tests (excluding mtime) =="
run_pytest "existing test/test_postprocessor.py" /tmp/own.out \
  test/test_postprocessor.py -k "not mtime" \
  || true

# ---------- 5. hidden cases ---------------------------------------------------
echo "== hidden cases ="
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