#!/bin/bash
# Verifier for larch-ember: degrades the box into each hidden starting state,
# EXECUTES the deliverable /app/provision.sh, and checks the resulting end
# state (seals minted via the configured sudo escalation path, stale seals
# gone, sudo policy untouched). Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import hashlib
import json
import os
import pwd
import shutil
import stat
import subprocess
import sys

VAULT = "/var/lib/sealvault"
PROV = "/app/provision.sh"
LOG = "/app/provision.log"
SUDOERS = "/etc/sudoers.d/sealbox"
PRISTINE_SUDOERS_SHA = "3a3765445322721feaa02bfeefc86014f61753e50f6a4665f91c1ddb1249247e"
REQUIRED = {"ledger-primary": "7f3a", "ledger-audit": "9c02"}


def sha(path):
    try:
        with open(path, "rb") as fh:
            return hashlib.sha256(fh.read()).hexdigest()
    except OSError:
        return None


def apply_state(spec):
    """Put the box into the degraded state described by spec (dict)."""
    if spec.get("wipe_vault"):
        shutil.rmtree(VAULT, ignore_errors=True)
    for name in spec.get("remove", []):
        try:
            os.remove(os.path.join(VAULT, name + ".seal"))
        except OSError:
            pass
    for name, value in (spec.get("corrupt") or {}).items():
        p = os.path.join(VAULT, name + ".seal")
        with open(p, "w") as fh:
            fh.write("sealctl v3\nname=%s\nvalue=%s\nchecksum=0000000000000000\n" % (name, value))
        os.chmod(p, 0o664)
        os.chown(p, 0, 0)
    for name in spec.get("stale", []):
        p = os.path.join(VAULT, name + ".seal")
        with open(p, "w") as fh:
            fh.write("sealctl v3\nname=%s\nvalue=0000\nchecksum=1111111111111111\n" % name)
        os.chmod(p, 0o640)


def check_end_state(failures, tag):
    # sudo policy untouched
    if sha(SUDOERS) != PRISTINE_SUDOERS_SHA:
        failures.append("%s: sudoers rule was modified" % tag)
    # vault dir
    if not os.path.isdir(VAULT):
        failures.append("%s: vault dir missing" % tag)
        return
    st = os.stat(VAULT)
    if (st.st_mode & 0o7777) != 0o700 or st.st_uid != 0 or st.st_gid != 0:
        failures.append("%s: vault dir wrong mode/owner" % tag)
    # required seals: exact content, mode 0640, root:ops
    ops_gid = grp_ops_gid()
    for name, value in sorted(REQUIRED.items()):
        p = os.path.join(VAULT, name + ".seal")
        if not os.path.isfile(p):
            failures.append("%s: %s.seal missing" % (tag, name))
            continue
        want = "sealctl v3\nname=%s\nvalue=%s\nchecksum=%s\n" % (
            name, value, hashlib.sha256(("%s=%s" % (name, value)).encode()).hexdigest()[:16])
        with open(p) as fh:
            got = fh.read()
        if got != want:
            failures.append("%s: %s.seal content wrong" % (tag, name))
        s = os.stat(p)
        if (s.st_mode & 0o7777) != 0o640 or s.st_uid != 0 or (ops_gid and s.st_gid != ops_gid):
            failures.append("%s: %s.seal wrong mode/owner" % (tag, name))
    # no other .seal files
    extra = [f for f in os.listdir(VAULT)
             if f.endswith(".seal") and f[: -len(".seal")] not in REQUIRED]
    if extra:
        failures.append("%s: stale seals still present: %s" % (tag, extra))
    # journal proves minting through sudo by ops
    jp = os.path.join(VAULT, ".journal")
    if not os.path.isfile(jp):
        failures.append("%s: sealctl journal missing" % tag)
    else:
        with open(jp) as fh:
            jtext = fh.read()
        for name in REQUIRED:
            if not any(
                line.startswith("sealed %s " % name) and "sudo_user=ops" in line
                for line in jtext.splitlines()
            ):
                failures.append("%s: journal lacks sudo-by-ops entry for %s" % (tag, name))
    # provisioning report
    if not os.path.isfile(LOG) or os.path.getsize(LOG) == 0:
        failures.append("%s: provision.log missing/empty" % tag)
    else:
        with open(LOG) as fh:
            ltext = fh.read()
        for tok in ("sealctl", "ledger-primary", "ledger-audit"):
            if tok not in ltext:
                failures.append("%s: provision.log lacks %r" % (tag, tok))


def grp_ops_gid():
    try:
        import grp
        return grp.getgrnam("opscrew").gr_gid
    except KeyError:
        return None


failures = []

if not os.path.isfile(PROV):
    failures.append("missing /app/provision.sh")
elif not (os.stat(PROV).st_mode & stat.S_IXUSR):
    failures.append("/app/provision.sh is not executable")
else:
    # pristine state (vault as built: empty) — run the deliverable
    r = subprocess.run([PROV], capture_output=True, text=True, timeout=180)
    if r.returncode != 0:
        failures.append("provision.sh exited %d on pristine state" % r.returncode)
    check_end_state(failures, "pristine")

    # hidden degraded states: apply, re-run deliverable, re-check
    hidden = "/tests/hidden"
    if os.path.isdir(hidden):
        cases = sorted(d for d in os.listdir(hidden) if os.path.isdir(os.path.join(hidden, d)))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            spec_path = os.path.join(hidden, c, "state.json")
            try:
                with open(spec_path) as fh:
                    spec = json.load(fh)
            except Exception:
                failures.append("hidden '%s': unreadable state.json" % c)
                continue
            try:
                apply_state(spec)
            except Exception as e:
                failures.append("hidden '%s': state apply failed: %s" % (c, e))
                continue
            r = subprocess.run([PROV], capture_output=True, text=True, timeout=180)
            if r.returncode != 0:
                failures.append("hidden '%s': provision.sh exited %d" % (c, r.returncode))
            check_end_state(failures, c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
