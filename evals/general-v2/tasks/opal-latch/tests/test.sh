#!/bin/bash
# Verifier for opal-latch (executes-deliverable).
#
# Enforces the no-modify rule on the supplied /app/data vault, then EXECUTES
# the deliverable /app/restore.py on a scratch copy of the visible vault and
# on every hidden vault under /tests/hidden. A restored tree must equal the
# reference original exactly (names + bytes, diff -r) with no leftover vault
# artifacts. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_INDEX_SHA="ddf02dd515a56f8184462f959ea702e668f92203e0623a2ffed47a4996e619f7"

no_modify_broken=0
if [ ! -f /app/data/index.json ]; then
    echo "no-modify: /app/data/index.json missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/data/index.json | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_INDEX_SHA" ]; then
        echo "no-modify: /app/data was modified" >&2
        no_modify_broken=1
    fi
fi
if [ ! -d /app/data/blobs ]; then
    echo "no-modify: /app/data/blobs missing" >&2
    no_modify_broken=1
fi

python3 - "$no_modify_broken" <<'PY'
import os
import shutil
import subprocess
import sys

RESTORE = "/app/restore.py"
no_modify_broken = int(sys.argv[1])
failures = []


def restore_and_compare(vault_src, expected_dir, label):
    """Copy vault_src to scratch, run restore.py in place, diff vs expected."""
    work = "/tmp/opal_latch_case"
    shutil.rmtree(work, ignore_errors=True)
    shutil.copytree(vault_src, work, symlinks=True)
    try:
        r = subprocess.run([sys.executable, RESTORE, work],
                           capture_output=True, text=True, timeout=120)
    except Exception as exc:
        failures.append("%s: restore.py raised %s" % (label, exc))
        return
    if r.returncode != 0:
        failures.append("%s: restore.py exited %d (%s)"
                        % (label, r.returncode, (r.stderr or "").strip()[-200:]))
        return
    if os.path.exists(os.path.join(work, "blobs")):
        failures.append("%s: blobs/ still present after restore" % label)
    if os.path.exists(os.path.join(work, "index.json")):
        failures.append("%s: index.json still present after restore" % label)
    rc = subprocess.run(["diff", "-r", expected_dir, work],
                        capture_output=True, text=True)
    if rc.returncode != 0:
        failures.append("%s: restored tree differs from original: %s"
                        % (label, (rc.stdout + rc.stderr).strip()[:300]))


if not os.path.isfile(RESTORE):
    failures.append("missing /app/restore.py")

if no_modify_broken:
    failures.append("visible vault /app/data modified or missing (no-modify rule)")
elif not failures:
    if not os.path.isdir("/tests/visible-original"):
        failures.append("verifier fixture missing: /tests/visible-original")
    else:
        restore_and_compare("/app/data", "/tests/visible-original", "visible")

hidden = "/tests/hidden"
if os.path.isdir(hidden):
    cases = sorted(d for d in os.listdir(hidden)
                   if os.path.isdir(os.path.join(hidden, d)))
    if len(cases) < 2:
        failures.append("too few hidden cases")
    for c in cases:
        vault = os.path.join(hidden, c, "reshard")
        orig = os.path.join(hidden, c, "original")
        if not (os.path.isdir(vault) and os.path.isdir(orig)):
            failures.append("hidden case %s malformed (need reshard/ + original/)" % c)
            continue
        restore_and_compare(vault, orig, "hidden:%s" % c)
else:
    failures.append("no /tests/hidden directory")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
