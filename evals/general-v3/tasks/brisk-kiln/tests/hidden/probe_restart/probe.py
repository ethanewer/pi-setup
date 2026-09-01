#!/usr/bin/env python3
"""Hidden probe: restart persistence. Restarts the daemon via the control
script (the daemon only ever reads the canonical config path), then confirms
the configuration is honored again and the spool archives survived. Exits 0
on success."""
import subprocess
import sys
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:8418"
CTL = "/opt/listd/ctl.sh"

SPEC = {
    "announce": (True, {"ops@grebe-lake.net", "warden@grebe-lake.net"}),
    "alerts": (True, {"ops@grebe-lake.net"}),
    "chatter": (False, {"rosa@grebe-lake.net", "finn@example.org"}),
}


def req(path):
    try:
        with urllib.request.urlopen(BASE + path, timeout=10) as resp:
            return resp.status, resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        return exc.code, ""
    except Exception:
        return 0, ""


def die(label, detail):
    print("probe_restart FAIL: %s (%s)" % (label, detail), file=sys.stderr)
    sys.exit(1)


def check(cond, label, detail=""):
    if not cond:
        die(label, detail)


def main():
    # Restart through the control script: the daemon reloads ONLY from the
    # canonical path, so this proves the configuration survives there.
    r = subprocess.run(["/opt/listd/ctl.sh", "restart"], timeout=60,
                       capture_output=True, text=True)
    check(r.returncode == 0, "ctl.sh restart",
          r.stderr[-300:] if r.stderr else str(r.returncode))

    import json
    code, body = req("/lists")
    check(code == 200, "lists after restart", str(code))
    try:
        obj = json.loads(body)
    except Exception as exc:
        die("lists parse after restart", "%s: %r" % (exc, body[:200]))
    lists = {l["name"]: l for l in obj.get("lists", [])}
    check(set(lists) == set(SPEC), "list names after restart", sorted(lists))
    for name, (closed, members) in SPEC.items():
        lst = lists.get(name)
        if lst is None:
            die("restart lists", "missing %s" % name)
        check(bool(lst["closed"]) == closed, "closed flag (%s)" % name, lst)
        # in-memory subscriptions do not persist; members come from the config
        check(sorted(lst["members"]) == sorted(members),
              "members from config (%s)" % name, lst["members"])

    # spool archives persist across the restart
    code, body = req("/archive/announce")
    check(code == 200, "announce archive persists", str(code))
    check("Subject: Weekly status" in body,
          "announce archive content persists", body[:300])

    code, body = req("/health")
    check(code == 200, "health after restart", str(code))
    try:
        assert json.loads(body).get("config") == "/etc/listd/lists.conf"
    except Exception as exc:
        die("health config", str(exc))

    print("probe_restart ok", file=sys.stderr)
    sys.exit(0)


if __name__ == "__main__":
    main()
