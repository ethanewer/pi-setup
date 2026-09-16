#!/usr/bin/env python3
"""Probe helpers for the yoke-inlet verifier.

All traffic is real: TLS through the agent's own CA bundle to the proxy, plain
HTTP to the two upstream apps, decided by the agent's nginx configuration.
Nothing here reads the agent's configuration or the nginx.conf to learn the
answers; every assertion comes from observed responses and the access log.

Subcommands:
    stop                                        kill listeners on 8123/8124/8443
    killport PORT...                            kill listeners on the given ports
    wait-ready CA HOST PORT TIMEOUT TAG         poll GET /healthz until 200
    split CA HOST PORT UA ROUTE...              300 requests; canary share band
    failover CA HOST PORT UA SURVIVOR ROUTE...  30 requests; all from survivor
    logcheck CA HOST PORT LOGFILE UA MIN ROUTE...  parse YOKE format; >= MIN
                               compliant lines must carry this UA
"""
import json
import os
import re
import signal
import ssl
import sys
import time
from http.client import HTTPSConnection

CANARY_PORT = 8123
STABLE_PORT = 8124
FRONT_PORT = 8443
STACK_PORTS = (CANARY_PORT, STABLE_PORT, FRONT_PORT)

SPLIT_N = 300
FAILOVER_N = 30
SPLIT_LOW = 0.60
SPLIT_HIGH = 0.72

UA_PAT = re.compile(r"[A-Za-z0-9._/-]{1,64}")
ISO_PAT = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}")
UPSTREAM_PAT = re.compile(r"127\.0\.0\.1:(8123|8124)(, 127\.0\.0\.1:(8123|8124))*")
DECIMALS_PAT = re.compile(r"-?[0-9]+(\.[0-9]+)?(, -?[0-9]+(\.[0-9]+)?)*")
TIME_PAT = re.compile(r"[0-9]+(\.[0-9]+)?")


def _ctx(ca):
    return ssl.create_default_context(cafile=ca)


def _get(host, port, ctx, path, ua, timeout=10):
    conn = HTTPSConnection(host, port, context=ctx, timeout=timeout)
    try:
        conn.request("GET", path, headers={"User-Agent": ua, "Connection": "keep-alive"})
        resp = conn.getresponse()
        body = resp.read()
        try:
            data = json.loads(body)
        except Exception:
            data = None
        return resp.status, data
    finally:
        conn.close()


# --------------------------------------------------------------------------
# process control
# --------------------------------------------------------------------------
def _listening_pids(port):
    want = {}
    for f in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(f).read().splitlines()[1:]
        except OSError:
            continue
        for ln in lines:
            parts = ln.split()
            if len(parts) < 10:
                continue
            try:
                phex = parts[1].rsplit(":", 1)[1]
                lport = int(phex, 16)
            except ValueError:
                continue
            if lport == port and parts[3] == "0A":  # LISTEN state
                want.setdefault(parts[9], True)
    pids = set()
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            fds = os.listdir("/proc/%s/fd" % pid)
        except OSError:
            continue
        for fd in fds:
            try:
                tgt = os.readlink("/proc/%s/fd/%s" % (pid, fd))
            except OSError:
                continue
            if tgt.startswith("socket:["):
                ino = tgt[8:-1]
                if ino in want:
                    pids.add(int(pid))
    return pids


def cmd_killport(ports):
    for port in ports:
        for pid in _listening_pids(port):
            try:
                os.kill(pid, signal.SIGTERM)
            except OSError:
                pass
    deadline = time.time() + 2.0
    while time.time() < deadline:
        busy = {p for p in ports if _listening_pids(p)}
        if not busy:
            break
        time.sleep(0.1)
    for port in ports:
        for pid in _listening_pids(port):
            try:
                os.kill(pid, signal.SIGKILL)
            except OSError:
                pass
    time.sleep(0.2)
    return 0


def cmd_stop():
    return cmd_killport(list(STACK_PORTS))


# --------------------------------------------------------------------------
# readiness / probes
# --------------------------------------------------------------------------
def cmd_wait_ready(ca, host, port, timeout, tag):
    ctx = _ctx(ca)
    deadline = time.time() + float(timeout)
    last = None
    while time.time() < deadline:
        try:
            status, data = _get(host, port, ctx, "/healthz", "yoke-ready/%s" % tag)
            last = status
            if status == 200:
                return 0
        except Exception as exc:
            last = exc
        time.sleep(0.5)
    print("wait-ready: no 200 within %ss (last=%r)" % (timeout, last))
    return 1


def _share_report(counts, total):
    can = counts.get("canary", 0)
    print("split: total=%d canary=%d (%.4f) stable=%d bad=%d" % (
        total, can, can / total if total else 0.0,
        counts.get("stable", 0), counts.get("bad", 0)))


def cmd_split(ca, host, port, ua, routes):
    ctx = _ctx(ca)
    counts = {"canary": 0, "stable": 0, "bad": 0}
    bad = []
    for i in range(SPLIT_N):
        path = routes[i % len(routes)]
        status, data = _get(host, port, ctx, path, ua)
        if status != 200 or not isinstance(data, dict) or data.get("banner") != "yoke":
            counts["bad"] += 1
            if len(bad) < 3:
                bad.append((i, path, status, data))
            continue
        srv = data.get("server")
        if srv == "canary":
            counts["canary"] += 1
        elif srv == "stable":
            counts["stable"] += 1
        else:
            counts["bad"] += 1
            if len(bad) < 3:
                bad.append((i, path, status, data))
    _share_report(counts, SPLIT_N)
    if counts["bad"]:
        print("split: non-conforming responses: %r" % bad)
        return 1
    share = counts["canary"] / SPLIT_N
    if not (SPLIT_LOW <= share <= SPLIT_HIGH):
        print("split: canary share %.4f outside [%.2f, %.2f]" % (share, SPLIT_LOW, SPLIT_HIGH))
        return 1
    return 0


def cmd_failover(ca, host, port, ua, survivor, routes):
    ctx = _ctx(ca)
    counts = {"ok": 0, "other": 0, "bad": 0}
    for i in range(FAILOVER_N):
        path = routes[i % len(routes)]
        status, data = _get(host, port, ctx, path, ua)
        if status == 200 and isinstance(data, dict) and data.get("server") == survivor:
            counts["ok"] += 1
        elif status == 200 and isinstance(data, dict):
            counts["other"] += 1
        else:
            counts["bad"] += 1
            line = "failover: req %d %s -> status=%s body=%r" % (i, path, status, data)
            print(line[:200])
    print("failover: ok=%d other=%d bad=%d (survivor=%s)" % (
        counts["ok"], counts["other"], counts["bad"], survivor))
    if counts["ok"] == FAILOVER_N:
        return 0
    return 1


# --------------------------------------------------------------------------
# access-log format
# --------------------------------------------------------------------------
def _record_ok(fields, ua):
    if len(fields) != 9:
        return False, "field count %d != 9" % len(fields)
    if fields[0] != "YOKE":
        return False, "prefix %r != YOKE" % fields[0]
    if not ISO_PAT.match(fields[1]):
        return False, "timestamp %r not ISO-8601" % fields[1]
    if fields[3] != "200":
        return False, "status %r != 200" % fields[3]
    if not fields[4].isdigit():
        return False, "bytes %r not an integer" % fields[4]
    if not UPSTREAM_PAT.match(fields[5]):
        return False, "upstream %r malformed" % fields[5]
    if not DECIMALS_PAT.match(fields[6]):
        return False, "upstream time %r malformed" % fields[6]
    if not TIME_PAT.match(fields[7]):
        return False, "request time %r malformed" % fields[7]
    if fields[8] != ua:
        return False, "ua %r != %r" % (fields[8], ua)
    if not fields[2].startswith("GET ") or not fields[2].endswith(" HTTP/1.1"):
        return False, "request line %r not a GET HTTP/1.1 line" % fields[2]
    return True, None


def cmd_logcheck(ca, host, port, logfile, ua, min_lines, routes):
    # ua and routes matter; ca/host/port kept for a uniform argv shape.
    # min_lines is the number of requests the calling phase actually sent with
    # this UA (300 for the split phase, 30 for the failover phase); every
    # request must have produced exactly one compliant line, so a stack that
    # only logs some requests (or fabricates a handful of canned lines) fails.
    try:
        lines = open(logfile, "r", errors="replace").read().splitlines()
    except OSError as exc:
        print("logcheck: cannot read %s: %s" % (logfile, exc))
        return 1
    ok = 0
    total = 0
    problems = []
    for route in routes:
        found = 0
        for ln in lines:
            fields = ln.split("|")
            if len(fields) == 9 and fields[2] == "GET %s HTTP/1.1" % route and fields[8] == ua:
                good, why = _record_ok(fields, ua)
                if good:
                    found += 1
                else:
                    problems.append("route %s: %s | %s" % (route, why, ln[:180]))
        total += found
        if found == 0:
            problems.append("route %s: no well-formed YOKE record with ua %s (lines with route: %d)" % (
                route, ua, sum(1 for ln in lines if "GET %s " % route in ln)))
        else:
            ok += 1
    if total < min_lines:
        problems.append("only %d compliant YOKE lines carry ua %s; expected %d" % (
            total, ua, min_lines))
    if problems:
        print("logcheck: %s" % problems[0])
        return 1
    print("logcheck: %d compliant YOKE records for ua %s across %d routes" % (
        total, ua, ok))
    return 0


def main():
    argv = sys.argv[1:]
    if not argv:
        print(__doc__)
        return 2
    cmd = argv[0]
    args = argv[1:]
    try:
        if cmd == "stop":
            return cmd_stop()
        if cmd == "killport":
            return cmd_killport([int(a) for a in args])
        if cmd == "wait-ready" and len(args) >= 5:
            return cmd_wait_ready(args[0], args[1], int(args[2]), args[3], args[4])
        if cmd == "split" and len(args) >= 5:
            return cmd_split(args[0], args[1], int(args[2]), args[3], args[4:])
        if cmd == "failover" and len(args) >= 6:
            return cmd_failover(args[0], args[1], int(args[2]), args[3], args[4], args[5:])
        if cmd == "logcheck" and len(args) >= 8:
            return cmd_logcheck(args[0], args[1], int(args[2]), args[3], args[4], int(args[5]), args[6:])
    except Exception as exc:  # never let a probe exception take down the shutdown
        print("probe error in %s: %r" % (cmd, exc))
        return 1
    print("usage: see module docstring")
    return 2


if __name__ == "__main__":
    sys.exit(main())