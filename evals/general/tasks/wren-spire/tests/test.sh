#!/usr/bin/env bash
# Verifier for wren-spire: proves /app/setup.sh provisions the canonical
# mailing-list configuration (fresh-state: existing /etc/listd/lists.conf is
# stripped and the daemon restarted first), checks /app/loaded.json, and
# replays hidden mail batches through the live listd daemon, comparing
# deliveries, rejections, and the archive. Writes REWARD (0/1) to
# /logs/verifier/reward.txt on every exit path.
set -u

mkdir -p /logs/verifier
printf 0 > /logs/verifier/reward.txt

CTL=/opt/listd/ctl.sh
CANONICAL=/etc/listd/lists.conf

reward=0
if python3 - "$CTL" "$CANONICAL" <<'PY'
import glob, json, os, shutil, subprocess, sys, time

CTL = sys.argv[1]
CANONICAL = sys.argv[2]
STATE = "/var/lib/listd/loaded.json"
SPOOL = "/var/spool/listd"
INCOMING = os.path.join(SPOOL, "incoming")
PROCESSED = os.path.join(SPOOL, "processed")
REJECTED = os.path.join(SPOOL, "rejected")
ARCHIVE = os.path.join(SPOOL, "archive")
MAIL = os.path.join(SPOOL, "mail")

EXPECTED_LISTS = [
    ("announce@hollowpine.example",
     frozenset(["iris@hollowpine.example", "wren@hollowpine.example"])),
    ("digest@hollowpine.example", frozenset()),
    ("observers@hollowpine.example",
     frozenset(["quill@hollowpine.example", "sable@hollowpine.example",
                "wren@hollowpine.example"])),
]

failures = []


def ctl(sub, timeout=60):
    return subprocess.run([CTL, sub], capture_output=True, text=True,
                          timeout=timeout)


def read_state():
    """Return normalized loaded lists [(address, frozenset(subs)), ...]."""
    with open(STATE, encoding="utf-8") as fh:
        doc = json.load(fh)
    out = []
    for item in doc.get("lists", []):
        addr = str(item.get("address", "")).strip().lower()
        subs = frozenset(str(s).strip().lower() for s in item.get("subscribers", []) if str(s).strip())
        out.append((addr, subs))
    return sorted(out)


def poll_state(want, timeout=30):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            last = read_state()
            if last == want:
                return True
        except Exception:
            pass
        time.sleep(0.5)
    print("poll_state: last=%r want=%r" % (last, want), file=sys.stderr)
    return False


def clean_spool():
    for d in (INCOMING, PROCESSED, REJECTED, ARCHIVE, MAIL):
        shutil.rmtree(d, ignore_errors=True)
        os.makedirs(d, exist_ok=True)


def collect():
    deliveries = set()
    for path in glob.glob(os.path.join(MAIL, "*", "*.json")):
        try:
            with open(path, encoding="utf-8") as fh:
                doc = json.load(fh)
            deliveries.add((str(doc.get("id", "")),
                            str(doc.get("recipient", "")).strip().lower()))
        except Exception:
            failures.append("unreadable mail file %s" % path)
    rejected = set()
    for path in glob.glob(os.path.join(REJECTED, "*.json")):
        try:
            with open(path, encoding="utf-8") as fh:
                doc = json.load(fh)
            rejected.add(str(doc.get("id", "")))
        except Exception:
            rejected.add(os.path.basename(path))
    archived = set()
    for path in glob.glob(os.path.join(ARCHIVE, "*", "*.json")):
        try:
            with open(path, encoding="utf-8") as fh:
                doc = json.load(fh)
            archived.add(str(doc.get("id", "")))
        except Exception:
            failures.append("unreadable archive file %s" % path)
    return deliveries, rejected, archived


# --- deliverables must exist -------------------------------------------------
if not os.path.isfile("/app/setup.sh"):
    print("verify failures: missing /app/setup.sh", file=sys.stderr)
    sys.exit(1)
if not os.path.isfile("/app/loaded.json"):
    print("verify failures: missing /app/loaded.json", file=sys.stderr)
    sys.exit(1)

ok = True

# --- fresh-state proof: strip existing config, restart, expect empty ---------
if os.path.exists(CANONICAL):
    shutil.move(CANONICAL, "/tmp/wren_spire_stripped_lists.conf")
try:
    ctl("restart")
except Exception as exc:
    failures.append("daemon restart failed (%s)" % exc)
    ok = False
if ok and not poll_state([], timeout=20):
    failures.append("daemon still shows lists after config strip+restart")
    ok = False

# --- run the provisioning deliverable ---------------------------------------
if ok:
    try:
        r = subprocess.run(["bash", "/app/setup.sh"], capture_output=True,
                           text=True, timeout=120)
        if r.returncode != 0:
            failures.append("setup.sh exited %d" % r.returncode)
            ok = False
    except Exception as exc:
        failures.append("setup.sh failed to run (%s)" % exc)
        ok = False

# --- the daemon must now have loaded exactly the required lists --------------
if ok and not poll_state(EXPECTED_LISTS, timeout=30):
    failures.append("daemon did not load the required lists from the "
                    "canonical config")
    ok = False

if ok and not os.path.isfile(CANONICAL):
    failures.append("canonical config %s missing after setup.sh" % CANONICAL)
    ok = False

# --- the committed deliverable /app/loaded.json must match -------------------
if ok:
    try:
        with open("/app/loaded.json", encoding="utf-8") as fh:
            doc = json.load(fh)
        got = sorted((str(i.get("address", "")).strip().lower(),
                      frozenset(str(s).strip().lower()
                                for s in i.get("subscribers", [])
                                if str(s).strip()))
                     for i in doc.get("lists", []))
        if got != sorted(EXPECTED_LISTS):
            failures.append("loaded.json does not match the required lists")
            ok = False
    except Exception as exc:
        failures.append("loaded.json unreadable (%s)" % exc)
        ok = False

# --- hidden mail batches through the live daemon -----------------------------
if ok:
    cases = 0
    for cdir in sorted(glob.glob("/tests/hidden/*/")):
        msgs = sorted(glob.glob(os.path.join(cdir, "messages", "*.json")))
        exp_path = os.path.join(cdir, "expected.json")
        if not msgs or not os.path.isfile(exp_path):
            failures.append("hidden '%s' malformed" % cdir)
            ok = False
            continue
        cases += 1
        name = os.path.basename(cdir.rstrip("/"))
        clean_spool()
        time.sleep(0.5)
        for m in msgs:
            shutil.copyfile(m, os.path.join(INCOMING, os.path.basename(m)))
        n = len(msgs)
        done = False
        deadline = time.time() + 30
        while time.time() < deadline:
            n_in = len(os.listdir(INCOMING))
            n_out = len(os.listdir(PROCESSED)) + len(os.listdir(REJECTED))
            if n_in == 0 and n_out >= n:
                done = True
                break
            time.sleep(0.25)
        time.sleep(0.5)
        if not done:
            failures.append("hidden '%s': daemon did not finish the batch" % name)
            ok = False
            continue
        deliveries, rejected, archived = collect()
        with open(exp_path, encoding="utf-8") as fh:
            exp = json.load(fh)
        want_del = sorted((d["id"], d["recipient"].strip().lower())
                          for d in exp.get("deliveries", []))
        want_rej = sorted(exp.get("rejected", []))
        want_arc = sorted(exp.get("archived", []))
        if sorted(deliveries) != want_del:
            failures.append("hidden '%s': deliveries mismatch" % name)
            ok = False
        if sorted(rejected) != want_rej:
            failures.append("hidden '%s': rejected mismatch" % name)
            ok = False
        if sorted(archived) != want_arc:
            failures.append("hidden '%s': archived mismatch" % name)
            ok = False
    if cases < 1:
        failures.append("no hidden cases")
        ok = False

if failures:
    print("verify failures: %s" % "; ".join(failures), file=sys.stderr)
sys.exit(0 if (ok and not failures) else 1)
PY
then
  reward=1
fi

echo "$reward" > /logs/verifier/reward.txt
exit 0
