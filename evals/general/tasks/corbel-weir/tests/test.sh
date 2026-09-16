#!/bin/bash
# corbel-weir verifier. The agent must have produced a correct click 8.5.0
# release from /app/src: sdist + wheel + release-proof.json. We independently
# create a fresh venv, install the agent's wheel with no network, check the
# installed metadata and public entry points against the release contract,
# sample that the wheel's code is byte-identical to the upstream checkout,
# rebuild a wheel from the sdist, run three hidden behavioural checks against
# the installed wheel, and run a subset of the project's own test suite
# against the installed wheel. Any failure -> reward 0.
# Guarantee a reward on every exit path.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier
reward=0
ok=1
fail() { echo "corbel-weir FAIL: $1" >&2; ok=0; }

WHEEL=/app/dist/click-8.5.0-py3-none-any.whl
SDIST=/app/dist/click-8.5.0.tar.gz
PROOF=/app/dist/release-proof.json
UPSTREAM_SHA=8b19813f2bfca99f1018a587a8cf54fc959f2e5d
VENV=/tmp/cw-v
RB=/tmp/cw-rb

# --- 1. deliverables exist at the contract paths -----------------------------
[ -f "$WHEEL" ] || fail "missing deliverable $WHEEL"
[ -f "$SDIST" ] || fail "missing deliverable $SDIST"
[ -f "$PROOF" ] || fail "missing deliverable $PROOF"

if [ $ok -eq 1 ]; then
  # --- 2. the agent's own release record must be consistent ------------------
  python3 - "$PROOF" <<'PY' || fail "release-proof.json invalid"
import json, sys
p = json.load(open(sys.argv[1]))
for key in ("version", "installed_version", "sdist_rebuild_version"):
    if p.get(key) != "8.5.0":
        print(f"release-proof field {key} = {p.get(key)!r}", file=sys.stderr)
        sys.exit(1)
if p.get("import_ok") is not True:
    print("release-proof import_ok not true", file=sys.stderr)
    sys.exit(1)
PY

  # --- 3. fresh venv, install the agent's wheel from disk, no network -------
  rm -rf "$VENV"
  python3 -m venv --system-site-packages "$VENV"
  "$VENV/bin/pip" install --no-index --no-deps --ignore-installed "$WHEEL" \
    >/tmp/cw-pip.log 2>&1 || fail "wheel did not install into a fresh venv"

  # --- 4. installed metadata, entry points, upstream identity ---------------
  (cd /tmp && "$VENV/bin/python" /tests/verify_installed.py "$UPSTREAM_SHA") \
    || fail "installed-package checks failed"

  # --- 5. the sdist must be standalone and still version 8.5.0 --------------
  rm -rf "$RB"
  mkdir -p "$RB"
  (cd /tmp && python3 -m build --no-isolation --wheel --outdir "$RB" "$SDIST") \
    >/tmp/cw-rb.log 2>&1 || { cat /tmp/cw-rb.log >&2; fail "sdist could not rebuild a wheel"; }
  (cd /tmp && "$VENV/bin/python" /tests/check_sdist_rebuild.py "$RB") \
    || fail "sdist-rebuilt wheel is not the 8.5.0 release"

  # --- 6. hidden behavioural checks, against the installed wheel only -------
  for c in c1 c2 c3; do
    (cd /tmp && "$VENV/bin/python" "/tests/hidden/$c/check.py") \
      || fail "hidden-$c behavioural check failed"
  done

  # --- 7. the project's own test suite, against the installed wheel ---------
  (cd /tmp && "$VENV/bin/python" -m pytest -q \
      /app/src/tests/test_basic.py /app/src/tests/test_chain.py) \
    >/tmp/cw-pytest.log 2>&1 || { tail -5 /tmp/cw-pytest.log >&2; fail "upstream pytest subset failed"; }
fi

[ $ok -eq 1 ] && reward=1
echo "$reward" > /logs/verifier/reward.txt
echo "corbel-weir reward=$reward" >&2
exit 0