#!/usr/bin/env python3
"""listd -- Hollowpine Observatory mailing-list manager.

Reads its list configuration EXCLUSIVELY from the canonical path
/etc/listd/lists.conf. Watches /var/spool/listd/incoming/ for JSON messages,
routes each to a configured list (archive + per-subscriber mailboxes) or to
rejected/. Publishes its currently loaded configuration to
/var/lib/listd/loaded.json. Re-reads the canonical config on SIGHUP and on
every loop iteration after a change is detected (mtime polling).
"""
import configparser
import json
import os
import shutil
import signal
import time

CONFIG_PATH = "/etc/listd/lists.conf"
STATE_PATH = "/var/lib/listd/loaded.json"
SPOOL = "/var/spool/listd"
INCOMING = os.path.join(SPOOL, "incoming")
PROCESSED = os.path.join(SPOOL, "processed")
REJECTED = os.path.join(SPOOL, "rejected")
ARCHIVE = os.path.join(SPOOL, "archive")
MAIL = os.path.join(SPOOL, "mail")

DIRS = (INCOMING, PROCESSED, REJECTED, ARCHIVE, MAIL, os.path.dirname(STATE_PATH))

_reload = True


def _hup(signum, frame):
    global _reload
    _reload = True


def ensure_dirs():
    for d in DIRS:
        os.makedirs(d, exist_ok=True)


def safe_name(value):
    value = "".join(c for c in str(value) if c.isalnum() or c in "._-")
    return value[:120] or "msg"


def parse_config(path):
    """Return the sorted list of {"address", "subscribers"} declarations."""
    if not os.path.isfile(path):
        return []
    cp = configparser.ConfigParser(interpolation=None)
    try:
        cp.read(path, encoding="utf-8")
    except Exception as exc:
        log("config parse error for %s: %s" % (path, exc))
        return []
    found = {}
    for section in cp.sections():
        name = section.strip()
        if not name.lower().startswith("list "):
            continue
        address = name[5:].strip().lower()
        if not address or "@" not in address:
            continue
        raw = ""
        try:
            if cp.has_option(section, "subscribers"):
                raw = cp.get(section, "subscribers")
        except Exception:
            raw = ""
        subs = []
        for part in raw.replace("\n", ",").split(","):
            s = part.strip().lower()
            if s and s not in subs:
                subs.append(s)
        found[address] = subs
    return [{"address": a, "subscribers": found[a]} for a in sorted(found)]


def log(msg):
    with open("/var/log/listd.log", "a", encoding="utf-8") as fh:
        fh.write("%s listd: %s\n" % (time.strftime("%Y-%m-%dT%H:%M:%S"), msg))


def write_state(lists):
    ensure_dirs()
    tmp = STATE_PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump({"config_path": CONFIG_PATH, "lists": lists}, fh, indent=2)
    os.replace(tmp, STATE_PATH)


def write_json(path, obj):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(obj, fh, indent=2)
    os.replace(tmp, path)


def deliver(msg, address, subs):
    mid = safe_name(msg.get("id", ""))
    local = address.split("@", 1)[0]
    adir = os.path.join(ARCHIVE, local)
    os.makedirs(adir, exist_ok=True)
    record = {"id": msg.get("id", ""), "to": address,
              "from": msg.get("from", ""), "subject": msg.get("subject", ""),
              "body": msg.get("body", "")}
    write_json(os.path.join(adir, mid + ".json"), record)
    for sub in subs:
        user = sub.split("@", 1)[0]
        mdir = os.path.join(MAIL, user)
        os.makedirs(mdir, exist_ok=True)
        mail = dict(record)
        mail["recipient"] = sub
        write_json(os.path.join(mdir, mid + ".json"), mail)


def main():
    signal.signal(signal.SIGHUP, _hup)
    ensure_dirs()
    lists_map = {}
    last_mtime = None
    while True:
        global _reload
        try:
            mtime = os.stat(CONFIG_PATH).st_mtime_ns
        except OSError:
            mtime = None
        if _reload or mtime != last_mtime:
            lists = parse_config(CONFIG_PATH)
            write_state(lists)
            lists_map = {l["address"]: l["subscribers"] for l in lists}
            log("loaded %d list(s) from %s" % (len(lists), CONFIG_PATH))
            _reload = False
            last_mtime = mtime
        try:
            for fname in sorted(os.listdir(INCOMING)):
                if not fname.endswith(".json"):
                    continue
                path = os.path.join(INCOMING, fname)
                try:
                    with open(path, encoding="utf-8") as fh:
                        msg = json.load(fh)
                    msg = dict(msg)
                except Exception:
                    dest = os.path.join(REJECTED, "bad-" + safe_name(fname))
                    shutil.move(path, dest)
                    continue
                to = str(msg.get("to", "")).strip().lower()
                if to in lists_map:
                    deliver(msg, to, lists_map[to])
                    shutil.move(path, os.path.join(PROCESSED, safe_name(fname)))
                else:
                    shutil.move(path, os.path.join(REJECTED, safe_name(fname)))
        except Exception as exc:
            log("loop error: %r" % (exc,))
        time.sleep(0.2)


if __name__ == "__main__":
    main()
