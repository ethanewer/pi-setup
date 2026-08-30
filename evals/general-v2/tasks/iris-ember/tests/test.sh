#!/bin/bash
# Verifier for tasks/iris-ember (executes-deliverable).
#
# Re-invokes the deliverable /app/schedule.py and independently checks each
# competency gate:
#   * availability minutes are parsed and the EARLIEST buffer-aware slot is
#     derived (independent recomputation, including the recovery-buffer-after-
#     late-meeting semantics) and emitted as a standards-conformant iCalendar
#     event at /app/earliest_slot.ics,
#   * the input availability directory is left byte-for-byte untouched,
#   * the discovery/driver step produced per-person snapshots matching the
#     provided person_producer.py tool, one per attendee,
#   * summary.txt exists and reports the same earliest slot (and the other
#     documented lines), and stdout carries the same EARLIEST_SLOT value.
# It then re-runs schedule.py over each hidden availability set in
# /tests/hidden/* using the documented `--avail <dir> --out <dir>` interface
# and independently re-checks these gates on those fresh, read-only inputs.
# Writes a numeric reward to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier

if [ ! -f /app/schedule.py ]; then
    echo "missing deliverable /app/schedule.py" >&2
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

python3 - <<'PYEOF'
import atexit
import datetime as dt
import hashlib
import json
import os
import shutil
import subprocess
import sys

failures = []
REWARD = "/logs/verifier/reward.txt"
HALL = "/tests/hidden"
TS_FMT = "%Y-%m-%dT%H:%M:%SZ"
COMPACT = "%Y%m%dT%H%M%S"

PRISTINE_SHA = {
    "config.json": "425923a3e5347e5eb6f8c405a71fd575e0fc5d2f176a51b711eec4c9955b99a9",
    "ada.avail":   "f99e15e60eb178a078876e7e38727392c527871c6acd2cd5935d43a8e7a18bb0",
    "bo.avail":    "85707848fde2e80b53b5a295cd5687e3f61307e41d7235031025e041dd85b346",
    "cy.avail":    "d1dcbb00eabf2dbcf6e1558d5b953e15f949e7522761a11ce840fdb2414f3e7a",
    "dee.avail":   "3dcef97477c67f5243eceb1e4593fd6dd46166e1cbeedc1ed47147c24166dee5",
}


def _fail_safe():
    """Crash-proofing: if the verifier dies mid-run for any reason the reward
    file must still exist (0), so a graded run can never be 'unverifiable'."""
    if not os.path.exists(REWARD):
        with open(REWARD, "w") as fh:
            fh.write("0")


atexit.register(_fail_safe)


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def sha(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def clock_dt(day, clock):
    hh, mm = clock.split(":")
    return day + dt.timedelta(minutes=int(hh) * 60 + int(mm))


def parse_busy(cfg_dir):
    """Parse every attendee .avail into effective (start, end) intervals.

    Malformed (end <= start), blank, or pipe-less lines are skipped. An
    interval whose END lands at/after late_hour on the target day is a late
    meeting: its effective end is extended by buffer_after_late_min.
    """
    with open(os.path.join(cfg_dir, "config.json")) as fh:
        cfg = json.load(fh)
    day = dt.datetime.strptime(cfg["target_date"], "%Y-%m-%d")
    late_cut = day.replace(hour=cfg["late_hour"], minute=0, second=0)
    buffer_delta = dt.timedelta(minutes=cfg["buffer_after_late_min"])
    busy = []
    for attendee in cfg["attendees"]:
        path = os.path.join(cfg_dir, attendee + ".avail")
        if not os.path.exists(path):
            continue  # a missing file means that attendee is fully free
        with open(path) as fh:
            for raw in fh:
                line = raw.strip()
                if not line or "|" not in line:
                    continue
                s, e = line.split("|")
                s_t = dt.datetime.strptime(s.strip(), TS_FMT)
                e_t = dt.datetime.strptime(e.strip(), TS_FMT)
                if e_t <= s_t:  # malformed / zero-length -> skip
                    continue
                eff = e_t + buffer_delta if e_t >= late_cut else e_t
                busy.append((s_t, eff))
    return busy, cfg


def reference_eval(cfg_dir):
    """Independently recompute the earliest buffer-aware conflict-free slot.

    Returns (earliest_dt_or_None, parsed_interval_count).
    """
    busy, cfg = parse_busy(cfg_dir)
    day = dt.datetime.strptime(cfg["target_date"], "%Y-%m-%d")
    start = clock_dt(day, cfg["window_start"])
    end_limit = clock_dt(day, cfg["window_end"])
    duration = dt.timedelta(minutes=cfg["duration_min"])
    step = dt.timedelta(minutes=cfg["step_min"])

    def conflicts(c):
        c_end = c + duration
        for s, e in busy:
            if c < e and c_end > s:
                return True
        return False

    c = start
    while c + duration <= end_limit:
        if not conflicts(c):
            return c, len(busy)
        c += step
    return None, len(busy)


def check_ics(path, cfg, expected):
    text = open(path, encoding="utf-8").read()
    lines = []
    for ln in text.splitlines():  # unfold folded lines
        if lines and ln.startswith(" "):
            lines[-1] += ln[1:]
        else:
            lines.append(ln)
    joined = "\n".join(lines)
    for token in ("BEGIN:VCALENDAR", "END:VCALENDAR", "BEGIN:VEVENT",
                  "END:VEVENT", "VERSION:2.0"):
        if token not in joined:
            failures.append("ICS missing %r in %s" % (token, path))
            return False
    for ln in text.splitlines():
        if len(ln.encode("utf-8")) > 75:
            failures.append("ICS line exceeds 75 octets: %s" % path)
            return False
    if expected is None:
        failures.append("ICS produced but no slot expected: %s" % path)
        return False

    def prop(name):
        for ln in lines:
            if ln.startswith(name + ":"):
                return ln.split(":", 1)[1]
        return None

    ds, de, su = prop("DTSTART"), prop("DTEND"), prop("SUMMARY")
    if not ds or not de or not su:
        failures.append("ICS missing DTSTART/DTEND/SUMMARY in %s" % path)
        return False
    if not ds.endswith("Z") or not de.endswith("Z"):
        failures.append("ICS times not UTC (Z): %s" % path)
    try:
        got_start = dt.datetime.strptime(ds[:-1], COMPACT)
        got_end = dt.datetime.strptime(de[:-1], COMPACT)
    except ValueError:
        got_start = got_end = None
    want_end = expected + dt.timedelta(minutes=cfg["duration_min"])
    if got_start != expected:
        failures.append("DTSTART %s != expected %s (%s)" % (ds, expected.strftime(COMPACT), path))
    if got_end != want_end:
        failures.append("DTEND %s != start+duration %s (%s)" % (de, want_end.strftime(COMPACT), path))
    if su.strip() != cfg["meeting_title"]:
        failures.append("SUMMARY %r != title %r" % (su, cfg["meeting_title"]))
    return True


def check_pristine(cfg_dir):
    got = {f: sha(os.path.join(cfg_dir, f))
           for f in os.listdir(cfg_dir)
           if f.endswith(".avail") or f == "config.json"}
    if set(got) != set(PRISTINE_SHA):
        failures.append("availability file set changed in %s" % cfg_dir)
        return
    for name, want in PRISTINE_SHA.items():
        if got.get(name) != want:
            failures.append("input file modified: %s/%s" % (cfg_dir, name))


def dir_snapshot(cfg_dir):
    out = {}
    for name in sorted(os.listdir(cfg_dir)):
        path = os.path.join(cfg_dir, name)
        if os.path.isfile(path) and (name.endswith(".avail") or name == "config.json"):
            out[name] = sha(path)
    return out


def check_unchanged(cfg_dir, before):
    if dir_snapshot(cfg_dir) != before:
        failures.append("input file modified in hidden set: %s" % cfg_dir)


def expected_personals(cfg):
    out = {}
    for attendee in cfg["attendees"]:
        r = run([sys.executable, "/app/tools/person_producer.py", "--person", attendee])
        if r.returncode != 0:
            failures.append("helper failed for %s" % attendee)
            out[attendee] = None
        else:
            out[attendee] = r.stdout
    return out


def check_personals(cfg, out_dir, personal_expected):
    # Per-person snapshot deliverable <out>/personals/*.txt (an "*.txt" file
    # per attendee). Expected contents are independently recomputed by running
    # the provided tool (expected_personals), then compared literally.
    pers_dir = os.path.join(out_dir, "personals")
    if not os.path.isdir(pers_dir):
        failures.append("missing personals dir: %s" % pers_dir)
        return
    for attendee in cfg["attendees"]:
        path = os.path.join(pers_dir, attendee + ".txt")
        if not os.path.isfile(path):
            failures.append("missing per-person file %s" % path)
            continue
        with open(path, encoding="utf-8") as fh:
            content = fh.read()
        if personal_expected.get(attendee) != content:
            failures.append("personals mismatch for %s (%s)" % (attendee, path))


def check_summary(cfg, out_dir, expected, parsed_count):
    path = os.path.join(out_dir, "summary.txt")
    if not os.path.isfile(path):
        failures.append("missing summary.txt (%s)" % path)
        return
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    got = {}
    for ln in text.splitlines():
        key, _, val = ln.partition("=")
        got[key.strip()] = val.strip()
    want = expected.strftime(COMPACT) + "Z" if expected else "none"
    if got.get("EARLIEST_SLOT") != want:
        failures.append("summary EARLIEST_SLOT %r != %r (%s)" % (got.get("EARLIEST_SLOT"), want, path))
    if got.get("MEETING_TITLE") != cfg["meeting_title"]:
        failures.append("summary MEETING_TITLE mismatch: %s" % path)
    for key, wantv in (("DURATION_MIN", cfg["duration_min"]),
                       ("LATE_HOUR", cfg["late_hour"]),
                       ("BUFFER_AFTER_LATE_MIN", cfg["buffer_after_late_min"]),
                       ("OCCUPIED_INTERVALS", parsed_count)):
        val = got.get(key)
        try:
            if val is None or int(val) != wantv:
                failures.append("summary %s=%r != %d (%s)" % (key, val, wantv, path))
        except ValueError:
            failures.append("summary %s=%r not an integer (%s)" % (key, val, path))


def check_stdout(text, where, expected):
    got = None
    for ln in text.splitlines():
        if ln.startswith("EARLIEST_SLOT="):
            got = ln[len("EARLIEST_SLOT="):].strip()
            break
    if got is None:
        failures.append("stdout missing EARLIEST_SLOT line (%s)" % where)
        return

    def canon(value):
        return "".join(ch for ch in value if ch not in "-:").lower()

    want = "none" if expected is None else canon(expected.strftime(COMPACT) + "Z")
    if canon(got) != want:
        failures.append("stdout EARLIEST_SLOT %r != expected %r (%s)" % (got, want, where))


def check_outputs(cfg, out_dir, expected, parsed_count, where):
    """Per-run gates shared by the default run and hidden-case runs."""
    ics = os.path.join(out_dir, "earliest_slot.ics")
    if os.path.exists(ics):
        check_ics(ics, cfg, expected)
    elif expected is not None:
        failures.append("%s: no ICS written" % where)
    check_personals(cfg, out_dir, expected_personals(cfg))
    check_summary(cfg, out_dir, expected, parsed_count)


# ---------------------------------------------------------------------------
# 0) Re-run the deliverable (documented default: read /app/availability ->
#    write /app).
# ---------------------------------------------------------------------------
r = run(["python3", "/app/schedule.py"])
if r.returncode != 0:
    failures.append("default schedule.py run failed rc=%d: %s" % (r.returncode, (r.stderr or "")[-300:]))
for need in ("/app/earliest_slot.ics", "/app/summary.txt"):
    if not os.path.exists(need):
        failures.append("default run did not produce %s" % need)

# 1) pristine guard + independent earliest + ICS + personals + summary + stdout.
if os.path.isdir("/app/availability"):
    check_pristine("/app/availability")
    cfg = json.load(open("/app/availability/config.json"))
    expected, parsed_count = reference_eval("/app/availability")
    check_outputs(cfg, "/app", expected, parsed_count, "default")
    check_stdout(r.stdout, "default", expected)
else:
    failures.append("no /app/availability directory")

# 2) hidden case generalization via the documented --avail/--out interface.
if os.path.isdir(HALL):
    for case in sorted(os.listdir(HALL)):
        cas_dir = os.path.join(HALL, case)
        if not os.path.isdir(cas_dir):
            continue
        before = dir_snapshot(cas_dir)
        the_top = "/tmp/iris_verify_" + case
        shutil.rmtree(the_top, ignore_errors=True)
        os.makedirs(the_top, exist_ok=True)
        cfg = json.load(open(os.path.join(cas_dir, "config.json")))
        expected, parsed_count = reference_eval(cas_dir)
        r = run(["python3", "/app/schedule.py", "--avail", cas_dir,
                 "--out", the_top])
        if r.returncode != 0:
            failures.append("hidden %s: run failed rc=%d: %s"
                            % (case, r.returncode, (r.stderr or "")[-300:]))
            check_unchanged(cas_dir, before)
            continue
        check_unchanged(cas_dir, before)
        check_outputs(cfg, the_top, expected, parsed_count, "hidden " + case)
        check_stdout(r.stdout, "hidden " + case, expected)

# 3) verdict: write a numeric reward in every path.
if failures:
    print("FAILURES:")
    for m in failures:
        print("  - " + m)
    with open(REWARD, "w") as fh:
        fh.write("0")
    sys.exit(0)

print("ALL PASS")
with open(REWARD, "w") as fh:
    fh.write("1")
sys.exit(0)
PYEOF