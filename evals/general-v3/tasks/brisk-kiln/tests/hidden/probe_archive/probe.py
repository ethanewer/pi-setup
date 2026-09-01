#!/usr/bin/env python3
"""Hidden probe: mbox archive content and headers (depends on the messages
posted by probe_acl). Exits 0 on success."""
import sys
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:8418"


def get(path):
    try:
        with urllib.request.urlopen(BASE + path, timeout=10) as resp:
            return resp.status, resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        return exc.code, ""
    except Exception:
        return 0, ""


def die(label, detail):
    print("probe_archive FAIL: %s (%s)" % (label, detail), file=sys.stderr)
    sys.exit(1)


def check(cond, label, detail=""):
    if not cond:
        die(label, detail)


def main():
    code, body = get("/archive/announce")
    check(code == 200, "announce archive status", str(code))
    for needle in ("From: ops@grebe-lake.net",
                   "To: announce@lists.grebe-lake.net",
                   "Subject: Weekly status",
                   "All systems nominal at the lake."):
        check(needle in body, "announce archive", "missing %r in %r"
              % (needle, body[:300]))
    # the rejected non-member post must NOT be in the archive
    check("intrusion" not in body,
          "announce archive contains rejected post", body[:300])

    code, body = get("/archive/chatter")
    check(code == 200, "chatter archive status", str(code))
    check("From: outsider@example.net" in body,
          "chatter archive sender", body[:300])
    check("Subject: hello from the shore" in body,
          "chatter archive subject", body[:300])

    code, body = get("/archive/alerts")
    check(code == 404, "alerts archive empty", str(code))

    code, _ = get("/archive/no-such-list")
    check(code == 404, "unknown list archive", str(code))

    print("probe_archive ok", file=sys.stderr)
    sys.exit(0)


if __name__ == "__main__":
    main()
