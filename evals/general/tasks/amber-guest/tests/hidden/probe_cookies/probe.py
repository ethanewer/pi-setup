#!/usr/bin/env python3
"""amber-guest hidden probe: the deterministic cookie store.

Plays a scripted exchange log (hidden from the agent) against the
``/app/httpkit/cookies.py`` CookieStore and
against an independent reference cookie model that re-derives every rule from the
documented contract.  After every operation the probe compares the full
store snapshot (ordered, exact dicts) and the Cookie header / request_cookies
output for several probe URLs, so any deviation in scoping, expiry, eviction
or assembly order fails immediately.

Exit code 0 = pass, 1 = fail.
"""
import sys

sys.path.insert(0, "/app")
import httpkit.cookies as dlv

# ---------------------------------------------------------------------------
# Independent reference model (functional style, derived from the contract).
# ---------------------------------------------------------------------------
import re
import email.utils
from urllib.parse import urlsplit

TOKEN_RE = re.compile(r"[A-Za-z0-9!#$%&'*+\-.^_`|~]+\Z")
INT_RE = re.compile(r"-?[0-9]+\Z")


def ref_split(url):
    p = urlsplit(url)
    host = p.hostname.lower() if p.hostname else None
    path = p.path or "/"
    return host, path


def ref_domain_ok(host, domain):
    return host == domain or host.endswith("." + domain)


def ref_path_ok(request_path, cook_path):
    if cook_path == "/":
        return request_path.startswith("/")
    return request_path == cook_path or \
        request_path.startswith(cook_path + "/")


def ref_default_path(url_path):
    if not url_path or url_path[0] != "/":
        return "/"
    i = url_path.rfind("/")
    return "/" if i <= 0 else url_path[:i]


def ref_parse(line, host, url_path, now):
    segs = line.split(";")
    head = segs[0]
    if "=" not in head:
        return None
    name, _, raw = head.partition("=")
    if not TOKEN_RE.fullmatch(name):
        return None
    value = raw.strip(" \t")

    domain = host
    path = ref_default_path(url_path)
    maxage = None
    expires = None
    for seg in segs[1:]:
        a, _, av = seg.partition("=")
        an = a.strip(" \t").lower()
        av = av.strip(" \t")
        if an == "domain":
            cand = av.lstrip(".").lower()
            if not cand or ("." not in cand and cand != "localhost") \
                    or not ref_domain_ok(host, cand):
                return None
            domain = cand
        elif an == "path":
            if not av.startswith("/"):
                return None
            path = av
        elif an == "max-age":
            if not INT_RE.fullmatch(av):
                return None
            maxage = int(av)
        elif an == "expires":
            try:
                dt = email.utils.parsedate_to_datetime(av)
            except (ValueError, TypeError):
                dt = None
            expires = int(dt.timestamp()) if dt is not None else None
    if maxage is not None:
        expires = now + maxage
    return {"name": name, "value": value, "domain": domain, "path": path,
            "created_at": now, "expires": expires}


def ref_store(model, line, url, now, cap):
    """Mutate model (list of records) per the documented rules."""
    host, url_path = ref_split(url)
    rec = ref_parse(line, host, url_path, now)
    if rec is None:
        return
    # prune expired (lazy)
    model[:] = [c for c in model if c["expires"] is None or c["expires"] > now]
    ident = (rec["domain"], rec["path"], rec["name"])
    idx = next((i for i, c in enumerate(model)
                if (c["domain"], c["path"], c["name"]) == ident), -1)
    if rec["expires"] is not None and rec["expires"] <= now:
        if idx >= 0:
            del model[idx]
        return
    if idx >= 0:
        model[idx]["value"] = rec["value"]
        model[idx]["expires"] = rec["expires"]
    else:
        model.append(rec)
    while len(model) > cap:
        model.sort(key=lambda c: (c["expires"] if c["expires"] is not None
                                  else float("inf"), c["created_at"],
                                  c["domain"], c["path"], c["name"]))
        del model[0]


def ref_applicable(model, url, now):
    host, url_path = ref_split(url)
    live = [c for c in model
            if c["expires"] is None or c["expires"] > now]
    out = [c for c in live
           if ref_domain_ok(host, c["domain"]) and ref_path_ok(url_path,
                                                               c["path"])]
    out.sort(key=lambda c: (-len(c["path"]), c["name"], c["domain"],
                            c["created_at"]))
    return out


def ref_header(model, url, now):
    return "; ".join("%s=%s" % (c["name"], c["value"])
                     for c in ref_applicable(model, url, now))


def ref_snapshot(model, now):
    live = [dict(c) for c in model
            if c["expires"] is None or c["expires"] > now]
    live.sort(key=lambda c: (c["domain"], c["path"], c["name"]))
    return live


failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)


def compare_state(jar, model, now, step):
    """Full state comparison after one operation."""
    got_snap = jar.snapshot()
    want_snap = ref_snapshot(model, now)
    if got_snap != want_snap:
        failures.append("step %s snapshot mismatch:\n  got= %r\n  want=%r"
                        % (step, got_snap, want_snap))
    for url in ("http://example.com/", "http://www.example.com/deep/a",
                "https://sub.example.com/x", "http://localhost/",
                "http://127.0.0.1/", "http://deep.sub.example.com/a/b"):
        gh = jar.cookie_header(url)
        wh = ref_header(model, url, now)
        if gh != wh:
            failures.append("step %s header(%s) mismatch: %r != %r"
                            % (step, url, gh, wh))
        grc = jar.request_cookies(url)
        wrc = [{"name": c["name"], "value": c["value"], "domain": c["domain"],
                "path": c["path"]} for c in ref_applicable(model, url, now)]
        if grc != wrc:
            failures.append("step %s request_cookies(%s) mismatch: %r != %r"
                            % (step, url, grc, wrc))


# ---------------------------------------------------------------------------
# The hidden scripted exchange log (fixed clock; never seen by the agent).
# ---------------------------------------------------------------------------
clock = [1000.0]
CAP = 5
jar = dlv.CookieStore(clock=lambda: clock[0], max_cookies=CAP)
model = []

SEQUENCE = [
    # (comment, op)   op: ("store", line, url) | ("tick", to) | ("clear",)
    ("default path /a/b from /a/b/c", ("store", "a=1",
                                       "http://example.com/a/b/c")),
    ("default path /a/b from /a/b/", ("store", "b=1",
                                      "http://example.com/a/b/")),
    ("default path / from /a", ("store", "c=1", "http://example.com/a")),
    ("explicit Path=/a win", ("store", "d=1; Path=/a",
                              "http://example.com/other")),
    ("same name different domain", ("store", "u=v1",
                                    "https://example.com/x")),
    ("subdomain default domain", ("store", "u=v2",
                                  "https://sub.example.com/x")),
    ("Domain strip dot + deep sub", ("store", "u=v3; Domain=.example.com",
                                     "https://deep.sub.example.com/y")),
    ("reject foreign domain", ("store", "bad=1; Domain=evil.test",
                               "http://example.com/")),
    ("reject no-dot domain", ("store", "bad2=1; Domain=example",
                              "http://example.com/")),
    ("reject bad path", ("store", "bad3=1; Path=x",
                         "http://example.com/")),
    ("reject bad max-age", ("store", "bad4=1; Max-Age=nope",
                            "http://example.com/")),
    ("reject no-name", ("store", "=x", "http://example.com/")),
    ("reject bad token name", ("store", "a b=1", "http://example.com/")),
    ("max-age live", ("store", "t1=1; Max-Age=50", "http://example.com/")),
    ("max-age zero deletes", ("store", "t2=1; Max-Age=0",
                              "http://example.com/")),
    ("max-age negative deletes", ("store", "t3=1; Max-Age=-3",
                                  "http://example.com/")),
    ("expires valid", ("store",
                       "e1=1; Expires=Sun, 06 Nov 1994 08:49:37 GMT",
                       "http://example.com/")),
    ("expires invalid -> session", ("store", "e2=1; Expires=tomorrow-ish",
                                    "http://example.com/")),
    ("max-age wins over expires", ("store",
                                   "e3=1; Expires=Sun, 06 Nov 1994 "
                                   "08:49:37 GMT; Max-Age=100",
                                   "http://example.com/")),
    ("port and userinfo ignored", ("store", "p1=1",
                                   "http://alice:pw@example.com:8080/z")),
    ("localhost domain", ("store", "l1=1",
                          "http://localhost/")),
    ("ip host keeps dots", ("store", "ip1=1",
                            "http://127.0.0.1/")),
    ("overwrite keeps created_at", ("store", "u=v9",
                                    "https://example.com/x")),
    ("tick past t1", ("tick", 1060.0)),
    ("store after expiry prunes", ("store", "after=1",
                                   "http://example.com/")),
    ("unnamed attributes ignored", ("store", "attr=1; Secure; HttpOnly; "
                                    "SameSite=Lax; unknown=whatever",
                                    "http://example.com/")),
]
for comment, op in SEQUENCE:
    kind = op[0]
    if kind == "store":
        _, line, url = op
        jar.store(line, url)
        ref_store(model, line, url, clock[0], CAP)
    elif kind == "tick":
        clock[0] = op[1]
        # lazy pruning is observed through the next operation / snapshot
    elif kind == "clear":
        jar.clear()
        model[:] = []
    compare_state(jar, model, clock[0], comment)

# set_cookies from a header list + parse_set_cookie surface checks
jar.clear()
model[:] = []
clock[0] = 2000.0
headers = [("Set-Cookie", "h1=1; Path=/api"),
           ("set-cookie", "h2=2"),
           ("Set-Cookie", "h3=3; Domain=.example.com; Max-Age=5"),
           ("Content-Type", "text/plain"),
           ("Set-Cookie", "h4=4; Path=/api/v1")]
jar.set_cookies(headers, "http://api.example.com/v1/users")
for name, val in headers:
    if name.lower() == "set-cookie":
        ref_store(model, val, "http://api.example.com/v1/users",
                  clock[0], CAP)
compare_state(jar, model, clock[0], "set_cookies round")

# eviction mixing session and expiring cookies (capacity widening)
jar = dlv.CookieStore(clock=lambda: clock[0], max_cookies=3)
model = []
clock[0] = 3000.0
for name, maxage in [("s1", None), ("s2", 10), ("s3", None), ("s4", 5),
                     ("s5", None), ("s6", 100)]:
    line = "%s=1" % name
    if maxage is not None:
        line += "; Max-Age=%d" % maxage
    jar.store(line, "http://example.com/")
    ref_store(model, line, "http://example.com/", clock[0], 3)
compare_state(jar, model, clock[0], "capacity eviction 1")

# tick so s2/s4 expire, then eviction must prefer sessions
clock[0] = 3007.0
jar.store("s7=1", "http://example.com/")
ref_store(model, "s7=1", "http://example.com/", clock[0], 3)
compare_state(jar, model, clock[0], "capacity eviction 2")

# parse_set_cookie surface: rejected -> None, valid -> documented keys
p = jar.parse_set_cookie("n=1; Path=/", "http://example.com/")
check(p is not None and set(p) == {"name", "value", "domain", "path",
                                   "created_at", "expires"},
      "parse_set_cookie keys: %r" % (p,))
check(jar.parse_set_cookie("x=1; Domain=no.test", "http://example.com/")
      is None, "parse rejection")
check(jar.parse_set_cookie("x=1; Path=bad", "http://example.com/") is None,
      "parse path rejection")
check(jar.parse_set_cookie("=v", "http://example.com/") is None,
      "parse empty name")

print("--- probe_cookies %d failure(s) ---" % len(failures))
for f in failures:
    print("FAIL:", f)
sys.exit(1 if failures else 0)