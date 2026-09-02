#!/bin/bash
# Verifier for "slate-fjord" (executes-deliverable).
# Enforces the server-integrity rules, checks the visible deliverables
# (/app/sync.sh, /app/clone), and EXECUTES the deliverable script on the
# visible remote and on every hidden case in /tests/hidden (fresh HOME,
# stdin at EOF, strict per-run timeout). Writes reward (0/1) to
# /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import json, os, re, shutil, subprocess, sys, tempfile

SYNC = "/app/sync.sh"
PASSWORD = "bedrock7"
USER = "deploy"

# Server-side sshd config must still be password-only (agent must not have
# reconfigured the daemon or its own account to dodge the automation).
failures = []

def sh(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)

def git(repo, *args, env=None):
    return sh(["git", "-C", repo, *args], env=env)

# --- 1. server integrity -----------------------------------------------------
cfg = ""
try:
    with open("/etc/ssh/sshd_config") as f:
        cfg = f.read()
except OSError:
    failures.append("sshd_config unreadable")
if "PubkeyAuthentication no" not in cfg or "PasswordAuthentication yes" not in cfg:
    failures.append("sshd_config auth policy was altered (password-only required)")

# --- 2. deliverable present; host-key checking must NOT be relaxed ----------
if not os.path.isfile(SYNC):
    failures.append("missing /app/sync.sh")
    print("verify failures:", failures)
    sys.exit(1)
try:
    script = open(SYNC).read()
except OSError:
    failures.append("/app/sync.sh unreadable")
    print("verify failures:", failures)
    sys.exit(1)
if re.search(r"StrictHostKeyChecking\s*[=\s]\s*[\"']?(no|accept-new)\b",
             script, re.I):
    failures.append("sync.sh relaxes or disables host-key checking")

def verifier_ssh_env():
    env = dict(os.environ)
    env["GIT_SSH_COMMAND"] = (
        f"sshpass -p {PASSWORD} ssh -o StrictHostKeyChecking=no "
        "-o UserKnownHostsFile=/dev/null -o PubkeyAuthentication=no "
        "-o PreferredAuthentications=password -o NumberOfPasswordPrompts=1"
    )
    return env

def fresh_home():
    return tempfile.mkdtemp(prefix="vhome-")

def run_sync(remote, target, message, timeout=60):
    """Execute the deliverable script exactly as the grader does."""
    home = fresh_home()
    env = dict(os.environ)
    env["HOME"] = home
    try:
        return subprocess.run(
            ["bash", SYNC, remote, target, message],
            capture_output=True, text=True, timeout=timeout,
            stdin=subprocess.DEVNULL, env=env,
        )
    except subprocess.TimeoutExpired:
        return None
    finally:
        shutil.rmtree(home, ignore_errors=True)

def inspect_remote(remote, dest):
    """Independent clone of the remote into dest; returns facts or None."""
    if os.path.exists(dest):
        shutil.rmtree(dest, ignore_errors=True)
    r = sh(["git", "clone", "-q", remote, dest], env=verifier_ssh_env())
    if r.returncode != 0:
        return None
    facts = {}
    b = git(dest, "symbolic-ref", "--short", "HEAD")
    facts["branch"] = b.stdout.strip()
    tip = git(dest, "log", "-1", "--format=%s")
    facts["tip"] = tip.stdout.strip()
    try:
        with open(os.path.join(dest, "manifest.txt")) as f:
            facts["manifest"] = f.read()
    except OSError:
        facts["manifest"] = None
    n = git(dest, "rev-list", "--count", "HEAD")
    facts["count"] = int(n.stdout.strip()) if n.returncode == 0 else None
    return facts

def check_case(name, remote, target, message, branch, keep, count_commits):
    """Run the deliverable script on a case and validate all outcomes."""
    if os.path.exists(target):
        shutil.rmtree(target, ignore_errors=True)
    run = run_sync(remote, target, message)
    if run is None:
        failures.append(f"{name}: sync.sh hung or timed out (interactive prompt?)")
        return
    if run.returncode != 0:
        failures.append(f"{name}: sync.sh exited {run.returncode}: "
                        f"{(run.stderr or run.stdout or '').strip()[:300]}")
        return
    u = git(target, "remote", "get-url", "origin")
    if u.returncode != 0 or u.stdout.strip() != remote:
        failures.append(f"{name}: origin is {u.stdout.strip()!r}, expected {remote!r}")
        return
    with tempfile.TemporaryDirectory(prefix="vrem-") as tmpdir:
        dest = os.path.join(tmpdir, "remoteclone")
        facts = inspect_remote(remote, dest)
        if facts is None:
            failures.append(f"{name}: could not independently clone the remote")
            return
        if facts["branch"] != branch:
            failures.append(f"{name}: remote branch is {facts['branch']!r}, "
                            f"expected {branch!r}")
        if facts["manifest"] != message + "\n":
            failures.append(f"{name}: manifest.txt is {facts['manifest']!r}")
        if facts["tip"] != message:
            failures.append(f"{name}: tip subject is {facts['tip']!r}, "
                            f"expected {message!r}")
        if count_commits is not None and facts["count"] != count_commits:
            failures.append(f"{name}: remote has {facts['count']} commits, "
                            f"expected {count_commits}")
        # re-runnability: a second identical run must also succeed
        run2 = run_sync(remote, target, message)
        if run2 is None or run2.returncode != 0:
            failures.append(f"{name}: second identical run failed "
                            "(sync must be re-runnable)")
        for rel, content in keep.items():
            kc = os.path.join(dest, rel)
            try:
                with open(kc) as f:
                    got = f.read()
            except OSError:
                got = None
            if got != content:
                failures.append(f"{name}: preserved file {rel} changed")

# --- 3. visible deliverable: /app/clone from the documented bootstrap run ----
VIS_REMOTE = "deploy@127.0.0.1:/srv/git/ledger.git"
if os.path.isdir("/app/clone/.git"):
    b = git("/app/clone", "symbolic-ref", "--short", "HEAD")
    if b.stdout.strip() != "main":
        failures.append("/app/clone is on branch %r, expected 'main'"
                        % b.stdout.strip())
    try:
        with open("/app/clone/manifest.txt") as f:
            m = f.read()
        if m != "bootstrap mirror\n":
            failures.append("/app/clone manifest.txt is %r" % m)
    except OSError:
        failures.append("/app/clone has no manifest.txt")
    u = git("/app/clone", "remote", "get-url", "origin")
    if u.stdout.strip() != VIS_REMOTE:
        failures.append("/app/clone origin is %r" % u.stdout.strip())
    head = git("/app/clone", "rev-parse", "HEAD").stdout.strip()
    with tempfile.TemporaryDirectory(prefix="vvis-") as tmpdir:
        facts = inspect_remote(VIS_REMOTE, os.path.join(tmpdir, "remoteclone"))
        if facts is None:
            failures.append("visible remote not cloneable at verify time")
        else:
            has = git(os.path.join(tmpdir, "remoteclone"),
                      "cat-file", "-e", head + "^{commit}")
            if has.returncode != 0:
                failures.append("/app/clone HEAD commit is not on the remote "
                                "(bootstrap run was not pushed)")
else:
    failures.append("missing /app/clone (run the documented bootstrap command)")

# --- 4. execute the deliverable on the visible case --------------------------
check_case("visible-ledger", VIS_REMOTE, "/tmp/vis-target", "bootstrap mirror",
           "main", {}, None)

# --- 5. hidden cases ---------------------------------------------------------
hidden_dir = "/tests/hidden"
if os.path.isdir(hidden_dir):
    cases = sorted(d for d in os.listdir(hidden_dir)
                   if os.path.isdir(os.path.join(hidden_dir, d)))
    if not cases:
        failures.append("no hidden cases present")
    for c in cases:
        cj = os.path.join(hidden_dir, c, "case.json")
        try:
            spec = json.load(open(cj))
        except Exception:
            failures.append("hidden '%s' malformed" % c)
            continue
        check_case("hidden-" + spec.get("name", c), spec["remote"],
                   os.path.join("/tmp/hidden-target", c), spec["message"],
                   spec["branch"], spec.get("keep", {}),
                   spec.get("count_commits"))
else:
    failures.append("hidden cases missing")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
