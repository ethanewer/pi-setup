#!/bin/bash
# Verifier for quiet-vellum: EXECUTES the deliverable /app/provision.sh on the
# visible case (twice, for idempotency) and on every hidden account/shell pair,
# and cross-checks the /app/shell_report.json deliverable against the real
# user-database lookup. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier

python3 - <<'PY'
import json, os, subprocess, sys

PROVISION = "/app/provision.sh"
REPORT = "/app/shell_report.json"
failures = []


def lookup(user):
    """Field 7 of `getent passwd <user>`; guarded parse, None on trouble."""
    try:
        r = subprocess.run(["getent", "passwd", user],
                           capture_output=True, text=True, timeout=30)
    except Exception as e:
        failures.append("getent %s failed: %s" % (user, e))
        return None
    if r.returncode != 0:
        failures.append("user-database lookup failed for %s" % user)
        return None
    fields = r.stdout.strip().split(":")
    if len(fields) != 7:
        failures.append("malformed passwd entry for %s: %r" % (user, r.stdout))
        return None
    return fields[6]


def provision(user, shell):
    try:
        r = subprocess.run(["bash", PROVISION, user, shell],
                           capture_output=True, text=True, timeout=60)
    except Exception as e:
        failures.append("provision %s %s crashed: %s" % (user, shell, e))
        return False
    if r.returncode != 0:
        failures.append("provision %s %s exited %d (%s)"
                        % (user, shell, r.returncode, r.stderr.strip()[:200]))
        return False
    return True


if not os.path.isfile(PROVISION):
    failures.append("missing /app/provision.sh")
else:
    # --- visible case: run the provisioner, twice (idempotency) ---
    provision("nightlog", "/bin/dash")
    provision("nightlog", "/bin/dash")
    actual = lookup("nightlog")
    if actual != "/bin/dash":
        failures.append("nightlog default shell is %r, want /bin/dash" % actual)

    # --- visible-case deliverable: the report must match reality ---
    if not os.path.isfile(REPORT):
        failures.append("missing /app/shell_report.json")
    else:
        try:
            with open(REPORT) as f:
                rep = json.load(f)
            if not isinstance(rep, dict):
                failures.append("shell_report.json is not an object")
            else:
                if set(rep.keys()) != {"user", "default_shell"}:
                    failures.append("shell_report.json keys: %r" % sorted(rep.keys()))
                else:
                    if rep["user"] != "nightlog":
                        failures.append("report user %r != nightlog" % rep["user"])
                    if actual is not None and rep["default_shell"] != actual:
                        failures.append("report default_shell %r != lookup %r"
                                        % (rep["default_shell"], actual))
        except Exception as e:
            failures.append("shell_report.json unreadable: %s" % e)

    # --- hidden cases: different existing users x other installed shells ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            args_path = os.path.join(base, "args.txt")
            exp_path = os.path.join(base, "expected.json")
            if not (os.path.isfile(args_path) and os.path.isfile(exp_path)):
                failures.append("hidden '%s' malformed" % c)
                continue
            try:
                toks = open(args_path).read().split()
            except Exception as e:
                failures.append("hidden '%s' args unreadable: %s" % (c, e))
                continue
            if len(toks) != 2:
                failures.append("hidden '%s' args malformed: %r" % (c, toks))
                continue
            user, shell = toks
            provision(user, shell)
            got = lookup(user)
            if got != shell:
                failures.append("hidden '%s': %s shell %r != %r" % (c, user, got, shell))
                continue
            try:
                with open(exp_path) as f:
                    want = json.load(f)
            except Exception as e:
                failures.append("hidden '%s' expected unreadable: %s" % (c, e))
                continue
            if want != {"user": user, "default_shell": shell}:
                failures.append("hidden '%s': account state wrong" % c)
    else:
        failures.append("no hidden cases directory")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

rc=$?
reward=0
if [ "$rc" -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
