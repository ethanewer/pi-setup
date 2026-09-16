#!/bin/bash
# Verifier for kedge-fairway: an upstream-clone debugging task on gallery-dl.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# zero-byte HTTP responses (Content-Length: 0) are downloaded as successful
# empty files instead of being refused with a warning.  The agent must also
# author its own failing reproduction (/app/reproduce.py), which the verifier
# runs against BOTH the pristine (unfixed) source and the repaired tree.
#
# The verifier:
#   0. restores the build-time sitecustomize.py from a host-uploaded pristine
#      copy (/tests/sitecustomize.pristine.py), so runtime behaviour is always
#      measured against the deliverable tree and not against startup hooks
#      (sitecustomize/.pth/...) an agent could plant in site-packages;
#   1. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, only the
#      minimal tracked source file is modified, and no new files appeared
#      inside the package);
#   2. asserts the fix landed in the deliverable source (behavioural checks
#      alone cannot separate a fixed tree from a runtime wrapper);
#   3. runs the agent's own reproduction /app/reproduce.py against the
#      PRISTINE source (reconstructed with `git show` of the pinned parent,
#      never shipped as bytes), which it must fail;
#   4. runs the agent's own reproduction against the REPAIRED tree, which it
#      must pass;
#   5. runs the project's own regression test for this bug, extracted at
#      image build time from the fix commit into /opt/golden (hash-checked);
#   6. runs the project's own downloader test suite (in-tree, parent version),
#      proving the fix broke nothing else;
#   7. runs authored hidden cases (zero-byte body with explicit content type
#      and extension; zero-length via the 206 Partial Content branch) that
#      the upstream test does not use.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=80a402f2673d0c8b5e5204be06fab706ae89e76a
FIX_SHA=63b57459483134ecb5bbe85a137736eb69cdf39f
GOLDEN=/opt/golden/test_downloader.py
GOLDEN_SHA256=4e897e59f6ff8e3d87c44b024cd046a0c86e95a4e28e1d790267cda4ce742305
PRISTINE_HTTP_SHA256=5a04228979d0f014d512368aa21183e663467d70beb332cce49118922601f8e2
SITECUSTOMIZE_SHA256=364576fd45a5e4094cd2db7d50f9d4978d9515e425fab37d20ce0a07cd8418a5
INTERP_MANIFEST=/tests/system-manifest.sha256
HTTP_FILE=$SRC/gallery_dl/downloader/http.py

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

# ---------- 0a. interpreter integrity (build-time manifest) -------------------
# The agent runs as root in this harness, so a planted sitecustomize.py, a
# .pth import hook, a patched _pytest or a golden-test swap could make an
# untouched buggy tree pass its own pytest gates.  /tests is uploaded only
# after the agent phase and is the only tree the agent cannot modify, so the
# build-time manifest of every file the interpreter can load (plus /opt/golden
# and the python binaries) is kept there and re-checked before anything runs.
echo "== interpreter integrity (build-time manifest) ="
gen_manifest () {
  {
    find /usr/local/lib/python3.12 -type f ! -path '*/__pycache__/*' -print0 \
      | sort -z | xargs -0 sha256sum
    find -L /usr/local/bin /usr/bin -maxdepth 1 -type f \( -name 'python*' -o -name 'pytest*' \) -print0 \
      | sort -z | xargs -0 sha256sum
    find /opt/golden -type f ! -path '*/__pycache__/*' -print0 \
      | sort -z | xargs -0 sha256sum
  }
}
if [ ! -s "$INTERP_MANIFEST" ]; then
  echo "FAIL: interpreter manifest missing from harness tests dir" >&2; reward=0
elif ! gen_manifest > /tmp/now-manifest.txt 2>/dev/null; then
  echo "FAIL: could not regenerate the interpreter manifest" >&2; reward=0
elif ! diff -u "$INTERP_MANIFEST" /tmp/now-manifest.txt > /tmp/manifest.diff 2>&1; then
  echo "FAIL: the Python interpreter tree, the python binaries or /opt/golden differ from the build-time manifest (an interception wrapper or a tampered golden test was left behind):" >&2
  head -12 /tmp/manifest.diff | sed 's/^/    /' >&2
  reward=0
else
  echo "ok: interpreter tree, python binaries and /opt/golden match the build-time manifest"
fi

# ---------- 0. harness plumbing restore ---------------------------------------
# The agent runs as root in the same filesystem the verifier later uses, so it
# could edit site-packages/sitecustomize.py (or plant other import hooks) to
# change behaviour without touching the checkout.  /tests is re-uploaded from
# the host at verify time, so the pristine copy of the build-time
# sitecustomize.py shipped beside this script is trustworthy: verify and
# restore it before any python run.
echo "== harness plumbing restore =="
PRISTINE_SITE=/tests/sitecustomize.pristine.py
if [ ! -s "$PRISTINE_SITE" ]; then
  echo "FAIL: pristine sitecustomize copy missing from /tests" >&2
  reward=0
elif [ "$(sha256sum "$PRISTINE_SITE" | cut -d' ' -f1)" != "$SITECUSTOMIZE_SHA256" ]; then
  echo "FAIL: /tests/sitecustomize.pristine.py does not match the build-time sitecustomize" >&2
  reward=0
elif ! cp "$PRISTINE_SITE" /usr/local/lib/python3.12/site-packages/sitecustomize.py; then
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
else
  echo "ok: upstream fix commit not reachable from the working clone"
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
bad=$(printf '%s\n' "$porcelain" | grep -v '^ M gallery_dl/downloader/http.py$' | grep -v '^?? ' || true)
if [ -n "$bad" ]; then
  echo "FAIL: unexpected working-tree changes (only gallery_dl/downloader/http.py may be modified):" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
fi
newpkg=$(printf '%s\n' "$porcelain" | grep '^?? gallery_dl/' || true)
if [ -n "$newpkg" ]; then
  echo "FAIL: new files were added inside the gallery_dl package:" >&2
  printf '%s\n' "$newpkg" | head -5 | sed 's/^/    /' >&2
  reward=0
fi
if [ ! -f "$HTTP_FILE" ]; then
  echo "FAIL: gallery_dl/downloader/http.py is missing" >&2; reward=0
elif [ -z "$(git -C "$SRC" diff -- gallery_dl/downloader/http.py 2>/dev/null || true)" ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2
  reward=0
else
  echo "ok: the deliverable source was modified"
fi

# ---------- 2. the fix must live in the deliverable source --------------------
# Behavioural checks alone cannot distinguish a fixed tree from a runtime
# wrapper over the buggy tree (sitecustomize/.pth/poisoned bytecode).  The
# correct handling requires the zero-length short-circuit in the size check of
# HttpDownloader.download, which logs the warning the regression test asserts.
echo "== the fix must be in the deliverable source =="
if grep -q 'self.log.warning("Empty file")' "$HTTP_FILE" 2>/dev/null; then
  echo "ok: zero-length warning present in the deliverable source"
else
  echo "FAIL: no zero-length handling in the deliverable gallery_dl/downloader/http.py -- the observable behaviour must come from a real fix in the tree, not from a runtime wrapper" >&2
  reward=0
fi

# ---------- 3. agent's reproduction against the PRISTINE tree ----------------
echo "== reproduction vs pristine (unfixed) source =="
if [ ! -s /app/reproduce.py ]; then
  echo "FAIL: /app/reproduce.py is missing (the agent must author its own reproduction)" >&2
  reward=0
else
  cp "$HTTP_FILE" /tmp/agent_http.py
  git -C "$SRC" show HEAD:gallery_dl/downloader/http.py > "$HTTP_FILE"
  if [ "$(sha256sum "$HTTP_FILE" | cut -d' ' -f1)" != "$PRISTINE_HTTP_SHA256" ]; then
    echo "FAIL: could not reconstruct the pristine downloader source" >&2
    reward=0
  else
    ( cd /tmp && timeout 300 python3 /app/reproduce.py > /tmp/repro-pristine.out 2>&1 )
    rc=$?
    cp /tmp/agent_http.py "$HTTP_FILE"
    if [ "$rc" -eq 0 ]; then
      echo "FAIL: /app/reproduce.py exited 0 on the pristine source, but the bug must be detectable there" >&2
      sed 's/^/    /' /tmp/repro-pristine.out >&2
      reward=0
    elif [ "$rc" -eq 124 ]; then
      echo "FAIL: /app/reproduce.py did not terminate within 300s against the pristine source" >&2
      reward=0
    else
      echo "ok: /app/reproduce.py detected the bug on the pristine source (exit $rc)"
    fi
  fi
  cp /tmp/agent_http.py "$HTTP_FILE"
fi

# ---------- 4. agent's reproduction against the REPAIRED tree ----------------
echo "== reproduction vs repaired tree =="
if [ ! -s /app/reproduce.py ]; then
  echo "FAIL: /app/reproduce.py is missing" >&2
  reward=0
else
  ( cd /tmp && timeout 300 python3 /app/reproduce.py > /tmp/repro-fixed.out 2>&1 )
  rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "ok: /app/reproduce.py passes on the repaired tree"
  else
    echo "FAIL: /app/reproduce.py failed on the repaired tree (exit $rc)" >&2
    sed 's/^/    /' /tmp/repro-fixed.out >&2
    reward=0
  fi
fi

# ---------- 5. golden: the upstream regression test ---------------------------
echo "== golden test (upstream regression tests for this bug) ="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
elif [ "$(sha256sum "$GOLDEN" | cut -d' ' -f1)" != "$GOLDEN_SHA256" ]; then
  echo "FAIL: golden test file was modified (tampered with)" >&2; reward=0
else
  echo "ok: golden file hash matches the build-time extraction"
  run_pytest "golden downloader test file" /tmp/golden.out "$GOLDEN" \
    || true
fi

# ---------- 6. the project's own existing downloader suite -------------------
echo "== the project's own downloader tests (in-tree, parent version) =="
run_pytest "in-tree test/test_downloader.py" /tmp/own.out \
  test/test_downloader.py \
  || true

# ---------- 7. hidden cases ---------------------------------------------------
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