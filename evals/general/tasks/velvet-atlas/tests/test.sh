#!/bin/bash
# Verifier for velvet-atlas: checks /app/remaining.json against the pristine
# seed, confirms the visible deletions went through the API (audit trail),
# and EXECUTES the deliverable client (/app/deactivate.py) on a fresh visible
# emulator plus every hidden case in /tests/hidden. Writes REWARD (0/1) to
# /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
exec python3 - <<'PYEOF'
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

failures = []
SERVERS = []
TMP = []

APP_EMU = "/app/badgedesk.py"
CLIENT = "/app/deactivate.py"
REMAINING = "/app/remaining.json"


def log(*a):
    print("[verifier]", *a)


def load(path):
    with open(path) as fh:
        return json.load(fh)


def http(method, base, path):
    req = urllib.request.Request(base + path, method=method)
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            body = r.read().decode()
            return r.status, (json.loads(body) if body else {})
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        return e.code, (json.loads(body) if body else {})


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def start_emulator(store_dir, port):
    p = subprocess.Popen(
        [sys.executable, APP_EMU, "--store", store_dir, "--port", str(port)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    base = "http://127.0.0.1:%d" % port
    t0 = time.time()
    while time.time() - t0 < 15:
        try:
            st, _ = http("GET", base, "/health")
            if st == 200:
                SERVERS.append(p)
                return base
        except Exception:
            time.sleep(0.2)
    p.kill()
    raise RuntimeError("emulator on port %d did not come up" % port)


def fresh_store(seed_path):
    d = tempfile.mkdtemp(prefix="velvet_")
    TMP.append(d)
    shutil.copy(seed_path, os.path.join(d, "attendees.json"))
    return d


def check_run(mod, seed_path, targets, port, tag):
    """Run the deliverable client against a fresh emulator and check that
    exactly the targets disappear while survivors remain and authenticate."""
    store = fresh_store(seed_path)
    base = start_emulator(store, port)
    try:
        removed = mod.cancel_attendees(base, targets)
        if sorted(removed) != sorted(targets):
            failures.append("%s: cancel_attendees removed %s, expected %s"
                            % (tag, sorted(removed), sorted(targets)))
            return
        seed_rows = load(seed_path)["attendees"]
        seed_ids = [a["attendee_id"] for a in seed_rows]
        survivors = [i for i in seed_ids if i not in set(targets)]

        for t in targets:
            st, _ = http("GET", base, "/api/v1/attendees/" + str(t))
            if st != 404:
                failures.append("%s: target %s still present (GET %d)"
                                % (tag, t, st))
            st, _ = http("GET", base, "/api/v1/attendees/%s/badge" % t)
            if st != 404:
                failures.append("%s: target %s badge endpoint did not 404 (%d)"
                                % (tag, t, st))
        for s in survivors:
            st, row = http("GET", base, "/api/v1/attendees/" + str(s))
            if st != 200:
                failures.append("%s: survivor %s no longer queryable (GET %d)"
                                % (tag, s, st))
                continue
            st2, badge = http("GET", base, "/api/v1/attendees/%s/badge" % s)
            if st2 != 200 or not isinstance(badge, dict) \
                    or not badge.get("badge_code"):
                failures.append("%s: survivor %s cannot authenticate (badge %d)"
                                % (tag, s, st2))
        listed = mod.list_attendees(base)
        if sorted(a["attendee_id"] for a in listed) != sorted(survivors):
            failures.append("%s: list_attendees does not match survivors" % tag)
    finally:
        pass


def clean_up():
    for p in SERVERS:
        try:
            p.terminate()
        except Exception:
            pass
    time.sleep(0.3)
    for d in TMP:
        shutil.rmtree(d, ignore_errors=True)


# ------------------------------------------------------------- deliverables
if not os.path.isfile(CLIENT):
    failures.append("missing /app/deactivate.py")

# --- visible artifact: /app/remaining.json must match the pristine seed -----
vis_seed = load("/tests/visible_seed.json")["attendees"]
vis_targets = load("/tests/visible_targets.json")["cancel"]
if not os.path.isfile(REMAINING):
    failures.append("missing /app/remaining.json")
else:
    try:
        rem = load(REMAINING)
        assert isinstance(rem, dict), "not a dict"
        got_removed = sorted(str(x) for x in rem["removed"])
        got_remaining = sorted(a["attendee_id"] for a in rem["remaining"])
        want_removed = sorted(vis_targets)
        want_remaining = sorted(a["attendee_id"] for a in vis_seed
                                if a["attendee_id"] not in set(vis_targets))
        if got_removed != want_removed:
            failures.append("remaining.json removed=%s, expected %s"
                            % (got_removed, want_removed))
        if got_remaining != want_remaining:
            failures.append("remaining.json remaining does not equal "
                            "seed minus targets")
    except Exception as e:
        failures.append("remaining.json unreadable/malformed: %r" % e)

# --- audit trail: the visible deletions must have gone through the API ------
audit_path = "/app/store/audit.ndjson"
try:
    with open(audit_path) as fh:
        deleted = [json.loads(line).get("attendee_id")
                   for line in fh if line.strip()
                   and json.loads(line).get("op") == "attendee.delete"]
    for t in vis_targets:
        if t not in deleted:
            failures.append("audit trail has no API delete for target %s" % t)
except FileNotFoundError:
    failures.append("audit trail missing (work not done through the API)")
except Exception as e:
    failures.append("audit trail unreadable: %r" % e)

# --- execute the deliverable client on a fresh visible emulator -------------
if os.path.isfile(CLIENT):
    try:
        mod = load_module(CLIENT, "deactivate")
        cancel = getattr(mod, "cancel_attendees", None)
        listing = getattr(mod, "list_attendees", None)
        if not callable(cancel) or not callable(listing):
            failures.append("client missing callable "
                            "cancel_attendees/list_attendees")
        else:
            check_run(mod, "/tests/visible_seed.json", vis_targets, 8901,
                      "visible")
            # --- hidden cases: fresh rosters, different target sets ---------
            hidden = "/tests/hidden"
            if os.path.isdir(hidden):
                cases = sorted(os.listdir(hidden))
                if not cases:
                    failures.append("no hidden cases present")
                for i, c in enumerate(cases):
                    base_dir = os.path.join(hidden, c)
                    seed = os.path.join(base_dir, "seed.json")
                    tgt = os.path.join(base_dir, "targets.json")
                    if not (os.path.isfile(seed) and os.path.isfile(tgt)):
                        failures.append("hidden '%s' malformed" % c)
                        continue
                    check_run(mod, seed, load(tgt)["cancel"], 8910 + i,
                              "hidden:" + c)
            else:
                failures.append("no hidden dir")
    except Exception as e:
        failures.append("client execution failed: %r" % e)

clean_up()
print("verify failures:", failures)
with open("/logs/verifier/reward.txt", "w") as fh:
    fh.write("0" if failures else "1")
sys.exit(0)
PYEOF
