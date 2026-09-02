#!/usr/bin/env python3
"""Independent scenario verifier for drift-dial.

Given a scenario config (the ground-truth server source) and the JSON output
that /app/solve.py produced for that scenario, recompute the expected parsed
records / session values from the config and check they match exactly.

Usage: verify.py <config.json> <solve-output.json>
Exit code 0 on success, 1 on any mismatch.
"""
import json
import math
import sys


def fail(msg):
    print("VERIFY FAIL:", msg)
    sys.exit(1)


def main():
    cfg_path, out_path = sys.argv[1], sys.argv[2]
    cfg = json.load(open(cfg_path, encoding="utf-8"))
    out = json.load(open(out_path, encoding="utf-8"))

    qu = cfg.get("quirks", {})

    # ---- title ----
    if out.get("title") != cfg["title"]:
        fail("title mismatch: got %r want %r" % (out.get("title"), cfg["title"]))

    # ---- stations ----
    expected = []
    for st in cfg["stations"]:
        temp = st["temp"]
        city = st["city"]
        if st["id"] in qu.get("missing_cells", []):
            temp = None
        if st["id"] in qu.get("empty_city", []):
            city = ""
        expected.append(
            {"id": st["id"], "name": st["name"], "city": city, "tempF": temp})

    got = out.get("stations", [])
    if len(got) != len(expected):
        fail("station count: got %d want %d" % (len(got), len(expected)))

    for i, (g, e) in enumerate(zip(got, expected)):
        if g.get("id") != e["id"]:
            fail("station[%d].id: got %r want %r" % (i, g.get("id"), e["id"]))
        if g.get("name") != e["name"]:
            fail("station[%d].name: got %r want %r" % (i, g.get("name"), e["name"]))
        if g.get("city") != e["city"]:
            fail("station[%d].city: got %r want %r" % (i, g.get("city"), e["city"]))
        eg, ee = g.get("tempF"), e["tempF"]
        if eg is None or ee is None:
            if eg is not ee:
                fail("station[%d].tempF: got %r want %r" % (i, eg, ee))
        else:
            if not isinstance(eg, (int, float)) or abs(float(eg) - float(ee)) > 1e-6:
                fail("station[%d].tempF: got %r want %r" % (i, eg, ee))

    # ---- session ----
    sess = out.get("session", {})
    if sess.get("sid") != cfg["session"]["after"]:
        fail("session.sid: got %r want %r" % (sess.get("sid"), cfg["session"]["after"]))
    if sess.get("logged_in") is not True:
        fail("session.logged_in must be true")
    if sess.get("logged_out") is not True:
        fail("session.logged_out must be true")

    print("VERIFY OK (%s)" % cfg["title"])
    sys.exit(0)


if __name__ == "__main__":
    main()