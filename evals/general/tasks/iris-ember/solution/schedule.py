#!/usr/bin/env python3
"""Meridian meeting-scheduler / ICS producer.

Parses a directory of attendee availability minutes (one text file per
attendee, each line ``YYYY-MM-DDTHH:MM:SSZ|YYYY-MM-DDTHH:MM:SSZ`` giving an
occupied interval), finds the EARLIEST conflict-free slot for a target meeting
on a given day within a search window, honours a recovery buffer that must be
left empty after any occupied meeting that ends at or after ``late_hour``, and
emits:

  <out>/earliest_slot.ics         a standards-conformant iCalendar event
  <out>/personals/<attendee>.txt  a per-person schedule snapshot, produced by
                                  *discovering and running* the provided
                                  ``person_producer.py`` tool
  <out>/summary.txt               a short textual report

The input availability directory is strictly read-only here: nothing under it
is ever created, modified or deleted.

Usage:
  python3 schedule.py [--avail DIR] [--out DIR]
"""
import argparse
import datetime as dt
import json
import os
import subprocess
import sys

UTC = dt.timezone.utc
TS_FMT = "%Y-%m-%dT%H:%M:%SZ"


def parse_ts(text):
    return dt.datetime.strptime(text, TS_FMT)


def ts_compact(value):
    return value.strftime("%Y%m%dT%H%M%S")


def load_cfg(avail_dir):
    with open(os.path.join(avail_dir, "config.json"), encoding="utf-8") as fh:
        cfg = json.load(fh)

    def clock(value):
        hh, mm = value.split(":")
        return int(hh) * 60 + int(mm)

    day = dt.datetime.strptime(cfg["target_date"], "%Y-%m-%d")
    cfg["_day"] = day
    cfg["_window_start"] = day + dt.timedelta(minutes=clock(cfg["window_start"]))
    cfg["_window_end"] = day + dt.timedelta(minutes=clock(cfg["window_end"]))
    return cfg


def load_busy(cfg, avail_dir):
    """Return sorted list of (start, effective_end) occupied intervals.

    A busy interval whose END lands at/after late_hour on the target day is a
    "late meeting": a recovery buffer is appended to its end, so the effective
    interval blocks the calendar until end + buffer. Malformed (end <= start),
    blank, or zero-length lines are ignored.
    """
    late_cut = cfg["_day"].replace(hour=cfg["late_hour"], minute=0, second=0)
    buffer_delta = dt.timedelta(minutes=cfg["buffer_after_late_min"])
    busy = []
    for attendee in cfg["attendees"]:
        path = os.path.join(avail_dir, attendee + ".avail")
        if not os.path.exists(path):
            continue  # missing file -> that attendee is fully free
        with open(path, encoding="utf-8") as fh:
            for raw in fh:
                line = raw.strip()
                if not line or "|" not in line:
                    continue
                s, e = line.split("|")
                start = parse_ts(s.strip())
                end = parse_ts(e.strip())
                if end <= start:  # malformed / zero-length -> skip
                    continue
                eff_end = end + buffer_delta if end >= late_cut else end
                busy.append((start, eff_end))
    busy.sort(key=lambda kv: kv[0])
    return busy


def find_earliest(cfg, busy):
    duration = dt.timedelta(minutes=cfg["duration_min"])
    step = dt.timedelta(minutes=cfg["step_min"])
    start = cfg["_window_start"]
    end_limit = cfg["_window_end"]

    def conflicts(c_slot):
        c_end = c_slot + duration
        for s, e in busy:
            if c_slot < e and c_end > s:
                return True
        return False

    c = start
    while c + duration <= end_limit:
        if not conflicts(c):
            return c
        c += step
    return None


def write_ics(cfg, start, out_dir):
    duration = dt.timedelta(minutes=cfg["duration_min"])
    end = start + duration
    uid = "meridian-%s-%s@meridian.example" % (cfg["target_date"],
                                               start.strftime("%H%M%S"))
    dtstamp = dt.datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    attendee_lines = "\r\n".join(
        'ATTENDEE;CN="%s":mailto:%s@meridian.example' % (a, a)
        for a in cfg["attendees"])
    body = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//Meridian//ScheduleGen//EN",
        "CALSCALE:GREGORIAN",
        "BEGIN:VEVENT",
        "UID:" + uid,
        "DTSTAMP:" + dtstamp,
        "DTSTART:" + ts_compact(start) + "Z",
        "DTEND:" + ts_compact(end) + "Z",
        "SUMMARY:" + cfg["meeting_title"],
        attendee_lines,
        "DESCRIPTION:Earliest conflict-free Meridian sync (%d min)"
        % cfg["duration_min"],
        "END:VEVENT",
        "END:VCALENDAR",
    ]
    with open(os.path.join(out_dir, "earliest_slot.ics"), "w",
              encoding="utf-8", newline="") as fh:
        fh.write("\r\n".join(body))
        fh.write("\r\n")


def discover_producer():
    """Discovery step: locate the provided person_producer.py tool."""
    for root in ("/app", os.getcwd()):
        for dirpath, _dirnames, filenames in os.walk(root):
            if "person_producer.py" in filenames:
                return os.path.join(dirpath, "person_producer.py")
    return None


def write_personals(cfg, out_base):
    producer = discover_producer()
    if producer is None:
        return False
    pers_dir = os.path.join(out_base, "personals")
    os.makedirs(pers_dir, exist_ok=True)
    for attendee in cfg["attendees"]:
        got = subprocess.run([sys.executable, producer, "--person", attendee],
                             capture_output=True, text=True)
        if got.returncode != 0:
            return False
        with open(os.path.join(pers_dir, attendee + ".txt"), "w",
                  encoding="utf-8") as fh:
            fh.write(got.stdout)
    return True


def write_summary(cfg, start, busy, out_base):
    earliest = ts_compact(start) + "Z" if start is not None else "none"
    lines = [
        "EARLIEST_SLOT=%s" % earliest,
        "MEETING_TITLE=%s" % cfg["meeting_title"],
        "DURATION_MIN=%d" % cfg["duration_min"],
        "WINDOW=%s..%s" % (cfg["window_start"], cfg["window_end"]),
        "OCCUPIED_INTERVALS=%d" % len(busy),
        "LATE_HOUR=%02d" % cfg["late_hour"],
        "BUFFER_AFTER_LATE_MIN=%d" % cfg["buffer_after_late_min"],
    ]
    with open(os.path.join(out_base, "summary.txt"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--avail", default="/app/availability")
    ap.add_argument("--out", default="/app")
    args = ap.parse_args()

    cfg = load_cfg(args.avail)
    busy = load_busy(cfg, args.avail)
    earliest = find_earliest(cfg, busy)

    os.makedirs(args.out, exist_ok=True)

    if earliest is not None:
        write_ics(cfg, earliest, args.out)
    ok_personals = write_personals(cfg, args.out)
    write_summary(cfg, earliest, busy, args.out)

    print("EARLIEST_SLOT=%s" % (ts_iso(earliest) + "Z"
                                if earliest is not None else "none"))
    print("PERSONALS_OK=%s" % ok_personals)


def ts_iso(value):
    if value is None:
        return "none"
    return value.strftime("%Y-%m-%dT%H:%M:%S")


if __name__ == "__main__":
    main()