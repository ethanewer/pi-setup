#!/bin/bash
# Verifier for quiet-keel: executes the deliverable /app/set_shell.sh on the
# visible runbook entry and on hidden (user, shell) cases — including invalid
# ones that must fail cleanly — and checks the account-database lookup
# (getent passwd) reports the requested default shell with all other fields
# untouched. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import os
import subprocess

SCRIPT = "/app/set_shell.sh"
failures = []


def getent_line(user):
    r = subprocess.run(["getent", "passwd", user],
                       capture_output=True, text=True, timeout=30)
    out = r.stdout.strip()
    return out if out else None


def run_script(user, shell):
    return subprocess.run([SCRIPT, user, shell],
                          capture_output=True, text=True, timeout=60)


def parse_kv(path):
    """Guarded key=value parse; returns dict or None."""
    try:
        with open(path) as fh:
            kv = {}
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" not in line:
                    return None
                k, _, v = line.partition("=")
                kv[k.strip()] = v.strip()
            return kv
    except OSError:
        return None


if not os.path.isfile(SCRIPT) or not os.access(SCRIPT, os.X_OK):
    failures.append("missing or non-executable /app/set_shell.sh")
else:
    # ---------- visible runbook case ----------
    req = parse_kv("/app/requirement.txt")
    if not req or "user" not in req or "shell" not in req:
        failures.append("could not parse /app/requirement.txt")
    else:
        v_user, v_shell = req["user"], req["shell"]
        # pristine fields 1-6 for the visible account (from the image build)
        v_pristine = {
            "deploy-bot": "deploy-bot:x:1000:1000::/var/lib/deploy-bot",
            "audit-runner": "audit-runner:x:1001:1001::/var/lib/audit-runner",
            "pipeline-svc": "pipeline-svc:x:1002:1002::/var/lib/pipeline-svc",
        }
        before = getent_line(v_user)
        r = run_script(v_user, v_shell)
        if r.returncode != 0:
            failures.append("visible case: script exited %d (%s)"
                            % (r.returncode, r.stderr.strip()))
        else:
            after = getent_line(v_user)
            if not after:
                failures.append("visible case: user vanished from database")
            else:
                head = ":".join(after.split(":")[:6])
                shell_field = after.split(":")[6] if after.count(":") >= 6 else ""
                if head != v_pristine.get(v_user, head):
                    failures.append("visible case: fields other than shell changed: %s" % after)
                if shell_field != v_shell:
                    failures.append("visible case: lookup reports shell %r, want %r"
                                    % (shell_field, v_shell))
        # answer.txt must record the outcome
        try:
            with open("/app/answer.txt") as fh:
                content = fh.read()
        except OSError:
            content = None
        if content is None:
            failures.append("missing /app/answer.txt")
        elif content != "%s:%s\n" % (v_user, v_shell):
            failures.append("answer.txt is %r, want %r"
                            % (content, "%s:%s\n" % (v_user, v_shell)))

    # ---------- hidden cases ----------
    hidden_dir = "/tests/hidden"
    if not os.path.isdir(hidden_dir):
        failures.append("no hidden cases present")
    else:
        for case in sorted(os.listdir(hidden_dir)):
            base = os.path.join(hidden_dir, case)
            spec = parse_kv(os.path.join(base, "spec.txt"))
            if not spec or "user" not in spec or "shell" not in spec:
                failures.append("hidden '%s': bad spec" % case)
                continue
            user, shell = spec["user"], spec["shell"]
            expect_ok = os.path.isfile(os.path.join(base, "expect_ok"))
            expect_fail = os.path.isfile(os.path.join(base, "expect_fail"))
            if expect_ok == expect_fail:
                failures.append("hidden '%s': need exactly one of "
                                "expect_ok/expect_fail" % case)
                continue
            before = getent_line(user)
            r = run_script(user, shell)
            after = getent_line(user)
            if expect_fail:
                if r.returncode == 0:
                    failures.append("hidden '%s': expected non-zero exit" % case)
                if before != after:
                    failures.append("hidden '%s': account database changed on "
                                    "a case that must fail cleanly" % case)
            else:
                if r.returncode != 0:
                    failures.append("hidden '%s': exited %d (%s)"
                                    % (case, r.returncode, r.stderr.strip()))
                    continue
                if not after:
                    failures.append("hidden '%s': user vanished" % case)
                    continue
                # fields 1-6 must equal the pristine baseline shipped with the case
                try:
                    with open(os.path.join(base, "baseline.txt")) as fh:
                        baseline = fh.read().strip()
                except OSError:
                    baseline = None
                head = ":".join(after.split(":")[:6])
                shell_field = after.split(":")[6] if after.count(":") >= 6 else ""
                if baseline and head != baseline:
                    failures.append("hidden '%s': fields other than shell "
                                    "changed: %s" % (case, after))
                if shell_field != shell:
                    failures.append("hidden '%s': lookup reports shell %r, "
                                    "want %r" % (case, shell_field, shell))

print("verify failures:", failures)
import sys
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
