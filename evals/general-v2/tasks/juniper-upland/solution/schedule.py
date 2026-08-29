#!/usr/bin/env python3
"""Juniper Upland scheduling-desk worker.

Scans the requested meeting window minute-by-minute to find the earliest slot
of the required duration that (a) conflicts with no attendee's availability and
(b) does not intrude on the recovery buffer around any late-ending availability
block, then writes a standards-conformant UTC iCalendar event for that slot.

Usage:  python3 /app/schedule.py <input_dir> <output_dir>

<input_dir> holds request.json and an availability/ directory with one .ics per
attendee (named by the local part of their address).  The program only READS
the input; it writes nothing back.  <output_dir> receives earliest_slot.ics.
The chosen slot's UTCISg start is printed (ISO8601, e.g. 2026-03-16T17:45:00Z).

Rules (identical to the scheduling-desk specification):
  * A meeting of duration_minutes must lie entirely inside
    [window_begin, window_end).
  * A busy block [b,e) from any attendee forbids that interval outright.
  * A busy block is "late" when the UTC hour of its END `e` is >= late_hour_utc.
    For every late block the forbidden interval becomes the block expanded
    buffer_minutes BEFORE its start and buffer_minutes AFTER its end, i.e.
    [b - buffer, e + buffer). This models recovery time after a day's late
    session as well as wind-down time before the next one.
  * earliest = the smallest feasible slot start (step = 1 minute).
"""

import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone

UTC = timezone.utc


def parse_utc(s):
    return datetime.strptime(s, "%Y%m%dT%H%M%SZ").replace(tzinfo=UTC)


def parse_iso(s):
    return datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=UTC)


def fmt_ics(dt):
    return dt.strftime("%Y%m%dT%H%M%SZ")


def fmt_iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def read_busy(path):
    """Return sorted busy [(start,end)] for one attendee calendar.

    A missing file means the attendee is entirely free.  A VEVENT that lacks a
    parseable DTSTART or DTEND (or has a trailing timezone that is not UTC) is
    skipped rather than aborted; a wholly unreadable file is treated as free.
    """
    busy = []
    try:
        with open(path, "r", encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return busy
    for block in re.findall(r"BEGIN:VEVENT(.*?)END:VEVENT", text, re.S):
        ms = re.search(r"DTSTART:(\d{8}T\d{6}Z)", block)
        me = re.search(r"DTEND:(\d{8}T\d{6}Z)", block)
        if not ms or not me:
            continue
        try:
            start = parse_utc(ms.group(1))
            end = parse_utc(me.group(1))
        except ValueError:
            continue
        if end <= start:
            continue
        busy.append((start, end))
    busy.sort()
    return busy


def blocked_intervals(busy, wb, we, buffer_minutes, late_hour_utc):
    """Return the forbidden time spans for the meeting.

    Plain busy intervals forbid [a,e).  Late busy intervals additionally forbid
    the expanded [a - buffer, e + buffer) band.  Blocks are clamped to the day
    the window sits in so an early-morning buffer never reaches into midnight
    and changes same-day semantics.
    """
    day_start = wb.replace(hour=0, minute=0, second=0, microsecond=0)
    day_end = day_start + timedelta(days=1)
    blocks = []
    buf = timedelta(minutes=buffer_minutes)
    for a, e in busy:
        blocks.append((a, e))
        if e.hour >= late_hour_utc:
            lo = a - buf
            hi = e + buf
            blocks.append((max(lo, day_start), min(hi, day_end)))
    return blocks


def overlap(st, dur_minutes, blocks):
    en = st + timedelta(minutes=dur_minutes)
    for a, e in blocks:
        if st < e and en > a:
            return True
    return False


def find_earliest(req, avail_dir):
    m = req["meeting"]
    wb = parse_iso(m["window_begin"])
    we = parse_iso(m["window_end"])
    dur = m["duration_minutes"]
    buf = m["buffer_minutes"]
    late = m["late_hour_utc"]

    busy = []
    for email in m["attendees"]:
        local = email.split("@")[0]
        busy.extend(read_busy(os.path.join(avail_dir, local + ".ics")))
    blocks = blocked_intervals(busy, wb, we, buf, late)

    step = timedelta(minutes=1)
    start = wb
    while start + timedelta(minutes=dur) <= we:
        if not overlap(start, dur, blocks):
            return start
        start += step
    return None


def render_ics(req, start, dur, path):
    m = req["meeting"]
    end = start + timedelta(minutes=dur)
    uid = "upland-%s-%02d@juniper-upland.example" % (start.strftime("%Y%m%dT%H%M"), dur)
    lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//Juniper-Upland//Coordinator//EN",
        "CALSCALE:GREGORIAN",
        "METHOD:PUBLISH",
        "BEGIN:VEVENT",
        "UID:" + uid,
        "DTSTAMP:" + fmt_ics(start),
        "DTSTART:" + fmt_ics(start),
        "DTEND:" + fmt_ics(end),
        "SUMMARY:" + m["title"],
    ]
    for em in m["attendees"]:
        lines.append("ATTENDEE;CN=%s:mailto:%s" % (em, em))
    lines.append("END:VEVENT")
    lines.append("END:VCALENDAR")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\r\n".join(lines) + "\r\n")


def main(argv):
    if len(argv) != 3:
        sys.stderr.write(
            "usage: python3 schedule.py <input_dir> <output_dir>\n"
        )
        return 2
    input_dir, output_dir = argv[1], argv[2]
    os.makedirs(output_dir, exist_ok=True)
    with open(os.path.join(input_dir, "request.json"), "r", encoding="utf-8") as fh:
        req = json.load(fh)
    avail_dir = os.path.join(input_dir, "availability")
    m = req["meeting"]
    dur = m["duration_minutes"]
    start = find_earliest(req, avail_dir)
    out_path = os.path.join(output_dir, "earliest_slot.ics")
    if start is None:
        # No feasible slot: emit an empty, bare calendar (no VEVENT).
        with open(out_path, "w", encoding="utf-8") as fh:
            fh.write(
                "BEGIN:VCALENDAR\r\nVERSION:2.0\r\n"
                "PRODID:-//Juniper-Upland//Coordinator//EN\r\n"
                "END:VCALENDAR\r\n"
            )
        print("NONE")
        return 0
    render_ics(req, start, dur, out_path)
    print(fmt_iso(start))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))