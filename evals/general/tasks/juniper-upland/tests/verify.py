#!/usr/bin/env python3
"""Independent verifier for juniper-upland.

Recomputes the earliest buffer-aware slot from the availability data by an
independent brute force (it never imports /app/schedule.py) and validates that
the task's /app deliverables match it. Concretely it:

  * executes /app/schedule.py on the /app fixture and on every /tests/hidden/h*
    scenario into scratch workdirs and structurally checks each produced ICS
    (VCALENDAR framing, VERSION/PRODID, UTC stamps, earliest slot, duration,
    and one ATTENDEE per requested attendee);
  * checks the shipped availability inputs are byte-identical to the pristine
    copies kept at /tests/primary_ref (the agent must not have modified them);
  * re-replays the provided roster producer for each snapshot member and
    byte-compares /app/personals/<name>.txt to its live stdout;
  * checks /app/summary.txt names the earliest slot and every snapshot member.

Exit 0 == reward 1; nonzero otherwise.
"""

import glob
import hashlib
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone

UTC = timezone.utc


def fail(msg):
    print("FAIL: " + msg, file=sys.stderr)


# ---------------- independent ground-truth scheduler ----------------

def _read_busy(path):
    """Parse any-valid VEVENTs [b,e) from an availability calendar."""
    busy = []
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return busy
    for block in re.findall(r"BEGIN:VEVENT(.*?)END:VEVENT", text, re.S):
        ms = re.search(r"DTSTART:(\d{8}T\d{6}Z)", block)
        me = re.search(r"DTEND:(\d{8}T\d{6}Z)", block)
        if not ms or not me:
            continue
        try:
            s = datetime.strptime(ms.group(1), "%Y%m%dT%H%M%SZ").replace(tzinfo=UTC)
            e = datetime.strptime(me.group(1), "%Y%m%dT%H%M%SZ").replace(tzinfo=UTC)
            if e > s:
                busy.append((s, e))
        except ValueError:
            continue
    return busy


def expected_earliest(scen):
    """Return ISO start of the earliest feasible slot, or None if none."""
    req = json.load(open(os.path.join(scen, "request.json")))
    m = req["meeting"]
    wb = parse_iso(m["window_begin"])
    we = parse_iso(m["window_end"])
    dur = m["duration_minutes"]
    buf = timedelta(minutes=m["buffer_minutes"])
    late = m["late_hour_utc"]
    adir = os.path.join(scen, "availability")

    busy = []
    for email in m["attendees"]:
        local = email.split("@")[0]
        busy.extend(_read_busy(os.path.join(adir, local + ".ics")))

    day0 = wb.replace(hour=0, minute=0, second=0, microsecond=0)
    day1 = day0 + timedelta(days=1)
    blocks = []
    for a, e in busy:
        blocks.append((a, e))
        if e.hour >= late:                      # clock-time >= late_hour_utc
            blocks.append((max(a - buf, day0), min(e + buf, day1)))

    step = timedelta(minutes=1)
    cur = wb
    while cur + timedelta(minutes=dur) <= we:
        ok = True
        for ba, be in blocks:
            if cur < be and cur + timedelta(minutes=dur) > ba:
                ok = False
                break
        if ok:
            return cur.strftime("%Y-%m-%dT%H:%M:%SZ")
        cur += step
    return None


def parse_iso(s):
    return datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=UTC)


# ---------------- independent ICS reader ----------------

def read_ics(path):
    text = open(path, encoding="utf-8").read()
    ds = re.search(r"DTSTART:(\d{8}T\d{6}Z)", text)
    de = re.search(r"DTEND:(\d{8}T\d{6}Z)", text)
    return {
        "begin": text.lstrip().startswith("BEGIN:VCALENDAR"),
        "end": text.rstrip().endswith("END:VCALENDAR"),
        "version": "VERSION:2.0" in text,
        "prodid": bool(re.search(r"PRODID:", text)),
        "dstart": ds.group(1) if ds else None,
        "dend": de.group(1) if de else None,
        "dstart_iso": (datetime.strptime(ds.group(1), "%Y%m%dT%H%M%SZ")
                       .replace(tzinfo=UTC).strftime("%Y-%m-%dT%H:%M:%SZ"))
                      if ds else None,
        "attendees": [l.rsplit(":", 1)[-1] for l in
                      re.findall(r"^ATTENDEE[^\r\n]*", text, re.M)],
    }


def check_ics(path, scen, label):
    """Structurally validate the ICS against the independent expectation."""
    ok = True
    info = read_ics(path)
    if not (info["begin"] and info["end"]):
        fail("[%s] must begin BEGIN:VCALENDAR and end END:VCALENDAR" % label)
        ok = False
    if not info["version"]:
        fail("[%s] missing VERSION:2.0" % label)
        ok = False
    if not info["prodid"]:
        fail("[%s] missing PRODID" % label)
        ok = False
    if info["dstart"] is None or info["dend"] is None:
        fail("[%s] missing DTSTART/DTEND" % label)
        return ok
    if not (info["dstart"].endswith("Z") and info["dend"].endswith("Z")):
        fail("[%s] timestamps must be UTC (Z)" % label)
        ok = False

    req = json.load(open(os.path.join(scen, "request.json")))
    m = req["meeting"]
    exp = expected_earliest(scen)
    if exp is not None and info["dstart_iso"] != exp:
        fail("[%s] DTSTART %s != ground truth %s"
             % (label, info["dstart_iso"], exp))
        ok = False
    ds = datetime.strptime(info["dstart"], "%Y%m%dT%H%M%SZ").replace(tzinfo=UTC)
    de = datetime.strptime(info["dend"], "%Y%m%dT%H%M%SZ").replace(tzinfo=UTC)
    if (de - ds) != timedelta(minutes=m["duration_minutes"]):
        fail("[%s] duration does not equal %d minutes"
             % (label, m["duration_minutes"]))
        ok = False
    if set(info["attendees"]) != set(m["attendees"]):
        fail("[%s] ATTENDEE set mismatch" % label)
        ok = False
    return ok


def sha256(path):
    h = hashlib.sha256()
    h.update(open(path, "rb").read())
    return h.hexdigest()


def main():
    ok = True

    # 1. inputs untouched: /app/<primary> == /tests/primary_ref/... 
    for rel in ["request.json"] + sorted(
            glob.glob("availability/*.ics", root_dir="/app")):
        app_ = os.path.join("/app", rel)
        ref = os.path.join("/tests/primary_ref", rel)
        if not (os.path.exists(app_) and os.path.exists(ref)):
            fail("primary input %s not found on both sides" % rel)
            ok = False
            continue
        if sha256(app_) != sha256(ref):
            fail("availability input modified: %s" % rel)
            ok = False

    # 2. visible deliverables
    if not os.path.exists("/app/earliest_slot.ics"):
        fail("missing /app/earliest_slot.ics")
        ok = False
    else:
        ok = check_ics("/app/earliest_slot.ics", "/app", "visible") and ok

    # summary.txt
    if os.path.exists("/app/summary.txt"):
        sumtext = open("/app/summary.txt", encoding="utf-8").read()
        exp = expected_earliest("/app")
        if exp is not None and exp not in sumtext:
            fail("summary.txt does not name earliest slot %s" % exp)
            ok = False
        for n in ["ada", "ben", "carol", "gwen"]:
            if n not in sumtext:
                fail("summary.txt missing snapshot member %s" % n)
                ok = False
    else:
        fail("missing /app/summary.txt")
        ok = False

    # 3. per-person snapshots (re-discover the producer and compare bytes)
    req = json.load(open("/app/request.json"))
    members = req["snapshot_members"]
    if os.path.isdir("/app/personals"):
        present = set(os.path.basename(f)[:-4] for f in
                      glob.glob("/app/personals/*.txt"))
    else:
        present = set()
    for name in members:
        fn = "/app/personals/%s.txt" % name
        if not os.path.exists(fn):
            fail("missing /app/personals/%s.txt" % name)
            ok = False
            continue
        live = subprocess.run(["python3", "/app/kit/roster_feed.py", name],
                              capture_output=True, text=True)
        if live.returncode != 0:
            fail("roster_feed(%s) failed: %s" % (name, live.stderr.strip()))
            ok = False
            continue
        if open(fn, encoding="utf-8").read() != live.stdout:
            fail("snapshot %s.txt does not byte-match live feed" % name)
            ok = False
    if set(members) != present:
        fail("personals dir content mismatch: %r" % sorted(present))
        ok = False

    # 4. hidden generalization: run /app/schedule.py on each hidden scenario
    hidden = sorted(glob.glob("/tests/hidden/h*"))
    if not hidden:
        fail("no hidden scenarios present under /tests/hidden")
        ok = False
    for i, scen in enumerate(hidden):
        work = "/tmp/hwork_%d" % i
        os.makedirs(work, exist_ok=True)
        prog = subprocess.run(["python3", "/app/schedule.py", scen, work],
                              capture_output=True, text=True)
        if prog.returncode != 0:
            fail("schedule.py failed on %s: %s"
                 % (os.path.basename(scen), prog.stderr.strip()))
            ok = False
            continue
        ics = os.path.join(work, "earliest_slot.ics")
        if not os.path.exists(ics):
            fail("no ICS produced from %s" % os.path.basename(scen))
            ok = False
            continue
        ok = check_ics(ics, scen, "hidden/" + os.path.basename(scen)) and ok

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())