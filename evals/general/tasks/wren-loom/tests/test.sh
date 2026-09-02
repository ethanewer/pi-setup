#!/bin/bash
# Verifier for wren-loom: checks the visible-case deliverables, enforces the
# no-modify rule on the supplied spec fixture, EXECUTES /app/provision.sh on
# the visible spec (then validates the canonical config, the live daemon, and
# /app/lists_report.json) and on every hidden spec in /tests/hidden (validating
# the live daemon after each). Writes REWARD (0/1) to /logs/verifier/reward.txt
# on every exit path.
set -u

mkdir -p /logs/verifier
printf 0 > /logs/verifier/reward.txt

overall=1
finalize_reward() {
  if [ "${overall:-0}" = "1" ]; then
    printf 1 > /logs/verifier/reward.txt
  else
    printf 0 > /logs/verifier/reward.txt
  fi
}
trap 'finalize_reward' EXIT

python3 - <<'PY'
import hashlib
import json
import os
import socket
import subprocess
import sys

failures = []

PROVISION = "/app/provision.sh"
REPORT = "/app/lists_report.json"
SPEC = "/app/spec/lists.csv"
CONFIG = "/etc/loopd/lists.conf"
PORT = 7871

PRISTINE_SPEC_SHA = "f30e56c47bbdb7f64543a2e430c5a12eec52fea4585234e6ea7084fe504b4143"

# ---- no-modify guard on the supplied visible spec fixture -------------------
if not os.path.isfile(SPEC):
    failures.append("no-modify: %s missing" % SPEC)
else:
    actual = hashlib.sha256(open(SPEC, "rb").read()).hexdigest()
    if actual != PRISTINE_SPEC_SHA:
        failures.append("no-modify: %s was modified" % SPEC)


def query(cmd, timeout=10):
    s = socket.create_connection(("127.0.0.1", PORT), timeout)
    try:
        s.sendall((cmd + "\n").encode("utf-8"))
        buf = b""
        while not buf.endswith(b"\n"):
            chunk = s.recv(4096)
            if not chunk:
                break
            buf += chunk
        return buf.decode("utf-8").strip()
    finally:
        s.close()


def daemon_alive():
    try:
        return query("PING") == "PONG"
    except Exception:
        return False


def parse_config(path):
    """Parse the canonical config with the documented semantics."""
    lists = {}
    current = None
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("#") or line.startswith(";"):
                continue
            if line.startswith("[") and line.endswith("]"):
                current = line[1:-1].strip()
                lists[current] = {"address": "", "members": [], "enabled": False}
                continue
            if current is None or "=" not in line:
                continue
            key, _, val = line.partition("=")
            key = key.strip().lower()
            val = val.strip()
            if key == "address":
                lists[current]["address"] = val
            elif key == "members":
                lists[current]["members"] = [m.strip() for m in val.split(",") if m.strip()]
            elif key == "enabled":
                lists[current]["enabled"] = val.lower() == "true"
    return lists


def run_provision(spec):
    try:
        r = subprocess.run(["bash", PROVISION, spec],
                           capture_output=True, text=True, timeout=120)
    except Exception as exc:
        failures.append("provision run raised: %s" % exc)
        return False
    if r.returncode != 0:
        failures.append("provision run failed (rc=%s): %s"
                        % (r.returncode, r.stderr.strip()[:200]))
        return False
    return True


def check_daemon(expected, label):
    """expected: {'lists': [...], 'members': {...}, 'counts': {...}}"""
    if not daemon_alive():
        failures.append("%s: daemon not answering PING" % label)
        return
    try:
        listing = query("LISTS")
        got_lists = [] if listing in ("NONE", "", "UNKNOWN", "ERR") else listing.split(",")
        if got_lists != expected["lists"]:
            failures.append("%s: LISTS mismatch: %r != %r"
                            % (label, got_lists, expected["lists"]))
        for name in expected["lists"]:
            want_members = expected["members"][name]
            got_raw = query("MEMBERS %s" % name)
            got_members = [] if got_raw == "" else got_raw.split(",")
            if got_members != want_members:
                failures.append("%s: MEMBERS %s mismatch: %r != %r"
                                % (label, name, got_members, want_members))
            got_count = query("COUNT %s" % name)
            if got_count != str(expected["counts"][name]):
                failures.append("%s: COUNT %s mismatch: %r != %r"
                                % (label, name, got_count, expected["counts"][name]))
        # disabled/absent lists must answer UNKNOWN
        for name in expected.get("unknown", []):
            if query("MEMBERS %s" % name) != "UNKNOWN":
                failures.append("%s: MEMBERS %s should be UNKNOWN" % (label, name))
    except Exception as exc:
        failures.append("%s: daemon query error: %s" % (label, exc))


# ---- daemon must be up before anything else ---------------------------------
if not daemon_alive():
    failures.append("loopd daemon is not running on 127.0.0.1:7871")

if not os.path.isfile(PROVISION):
    failures.append("missing /app/provision.sh")
else:
    with open("/tests/expected.json", encoding="utf-8") as fh:
        visible = json.load(fh)

    # --- visible case: execute the deliverable on the supplied spec ---------
    if run_provision(SPEC):
        # canonical config must exist at the canonical path and match
        if not os.path.isfile(CONFIG):
            failures.append("canonical config %s missing after provisioning" % CONFIG)
        else:
            try:
                got = parse_config(CONFIG)
                want = visible["config"]
                if got != want:
                    failures.append("canonical config content mismatch")
            except Exception as exc:
                failures.append("canonical config unreadable: %s" % exc)
        # live daemon must honor the config
        check_daemon(visible["daemon"], "visible case")
        # /app/lists_report.json deliverable
        if not os.path.isfile(REPORT):
            failures.append("missing /app/lists_report.json")
        else:
            try:
                with open(REPORT, encoding="utf-8") as fh:
                    got = json.load(fh)
                if got != visible["report"]:
                    failures.append("lists_report.json does not match expected report")
            except Exception as exc:
                failures.append("lists_report.json unreadable: %s" % exc)

    # --- hidden cases: distinct specs against the live daemon ----------------
    hidden_dir = "/tests/hidden"
    if not os.path.isdir(hidden_dir) or not os.listdir(hidden_dir):
        failures.append("no hidden cases present")
    else:
        for case in sorted(os.listdir(hidden_dir)):
            base = os.path.join(hidden_dir, case)
            spec = os.path.join(base, "lists.csv")
            exp = os.path.join(base, "expected.json")
            if not (os.path.isfile(spec) and os.path.isfile(exp)):
                failures.append("hidden '%s' malformed" % case)
                continue
            if not run_provision(spec):
                continue
            try:
                with open(exp, encoding="utf-8") as fh:
                    expected = json.load(fh)
            except Exception as exc:
                failures.append("hidden '%s': unreadable expected: %s" % (case, exc))
                continue
            check_daemon(expected, "hidden case '%s'" % case)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then overall=1; else overall=0; fi
