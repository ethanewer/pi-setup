#!/bin/bash
# Oracle for harbor-watch: write the solve.py pipeline program, then RUN it on
# the primary case (starting the roster service itself, no --url) to produce
# /app/answer.json. Never reads /tests.
set -eu

SOLVER="/app/solve.py"
OUT="/app/answer.json"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""Harbor Watch pipeline: fetch live crew roster calendars, then summarize."""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.request

DOW_MIN = 1440


def minutes(t):
    return int(t[0:8]) * DOW_MIN + int(t[9:11]) * 60 + int(t[11:13])


def parse_ics(text):
    events = []
    for block in re.findall(r"BEGIN:VEVENT\r?\n(.*?)END:VEVENT", text, re.S):
        ms = re.search(r"DTSTART:(\d{8}T\d{6})", block)
        me = re.search(r"DTEND:(\d{8}T\d{6})", block)
        if not (ms and me):
            continue
        events.append((ms.group(1), me.group(1)))
    return events


def summarize(cfg, ics_by_key):
    keys = [p["key"] for p in cfg["crew"]]
    parsed = {k: parse_ics(ics_by_key[k]) for k in keys}
    calendars = {}
    for k in keys:
        evs = parsed[k]
        calendars[k] = {
            "events": len(evs),
            "first_start": min(s for s, _ in evs) if evs else None,
            "last_end": max(e for _, e in evs) if evs else None,
            "busy_minutes": sum(minutes(e) - minutes(s) for s, e in evs),
        }
    overlap = 0
    for i in range(len(keys)):
        for j in range(i + 1, len(keys)):
            for s1, e1 in parsed[keys[i]]:
                for s2, e2 in parsed[keys[j]]:
                    inter = min(minutes(e1), minutes(e2)) - max(minutes(s1), minutes(s2))
                    if inter > 0:
                        overlap += inter
    return {
        "task": "harbor-watch",
        "terminal": cfg["terminal"],
        "crew": keys,
        "calendars": calendars,
        "overlap_minutes": overlap,
    }


def http_get(url, token=None):
    req = urllib.request.Request(url)
    if token is not None:
        req.add_header("Authorization", "Bearer " + token)
    with urllib.request.urlopen(req, timeout=30) as resp:
        if resp.status != 200:
            raise RuntimeError("GET %s -> %d" % (url, resp.status))
        return resp.read()


def wait_health(base_url, deadline=60):
    end = time.time() + deadline
    while time.time() < end:
        try:
            if http_get(base_url + "/health") == b"ok":
                return
        except Exception:
            pass
        time.sleep(0.25)
    raise RuntimeError("service /health never came up at " + base_url)


def start_service(config_path):
    tmpdir = tempfile.mkdtemp(prefix="hw-served-")
    proc = subprocess.Popen(
        [sys.executable, "/app/tools/roster_service.py",
         "--config", config_path, "--port", "0", "--outdir", tmpdir],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    try:
        line = proc.stdout.readline()
        m = re.search(r"port=(\d+)", line)
        if not m:
            raise RuntimeError("service did not report a port: %r" % line)
        base_url = "http://127.0.0.1:%s" % m.group(1)
        wait_health(base_url)
        return proc, base_url
    except Exception:
        proc.terminate()
        raise


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--case", required=True)
    ap.add_argument("--url", default=None)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    config_path = os.path.join(args.case, "roster", "service_config.json")
    with open(config_path) as fh:
        cfg = json.load(fh)
    token = cfg["auth_token"]

    proc = None
    if args.url:
        base_url = args.url.rstrip("/")
        wait_health(base_url)
    else:
        proc, base_url = start_service(config_path)

    try:
        outdir = os.path.join(args.case, "out")
        os.makedirs(outdir, exist_ok=True)
        ics_by_key = {}
        for person in cfg["crew"]:
            key = person["key"]
            body = http_get("%s/roster/%s.ics" % (base_url, key), token)
            with open(os.path.join(outdir, key + ".ics"), "wb") as fh:
                fh.write(body)
            ics_by_key[key] = body.decode("utf-8")
        summary = summarize(cfg, ics_by_key)
        with open(args.out, "w") as fh:
            json.dump(summary, fh, indent=2)
    finally:
        if proc is not None:
            proc.terminate()
            try:
                proc.wait(timeout=10)
            except Exception:
                proc.kill()


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

# 2. Run the produced program on the primary case (service self-started) to
#    generate /app/answer.json.
python3 "$SOLVER" --case /app/data --out "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT" /app/data/out/