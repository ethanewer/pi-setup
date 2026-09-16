#!/usr/bin/env python3
"""escutcheon-cable verifier core.

The stack is assumed to already be up (test.sh runs /app/up.sh first). This
script reads the request scenarios under /tests/visible and /tests/hidden,
drives each request through the frontend with a fresh W3C traceparent, and
asserts:

  * the observable HTTP status matches the scenario;
  * the collector holds a single rooted span tree for the trace (one frontend
    root whose parent is the caller's span id, plus the expected number of
    backend spans each parented under the root), all sharing the trace id;
  * an error request produces an error span;
  * every structured log line that references the trace is valid JSON whose
    correlation field `trace_id` equals the trace id, on both frontend and
    backend log files (the backend having the id proves propagation);
  * at least one valid frontend and one valid backend log line carry the id.

Exits 0 only when every scenario passes; otherwise prints a readable failure
list and exits 1 (test.sh writes the reward).
"""
import json
import os
import random
import sys
import time
import urllib.error
import urllib.request

FRONT = "http://127.0.0.1:8000"
COLLECTOR = "http://127.0.0.1:9100"
LOG_FRONT = "/app/.logs/frontend.jsonl"
LOG_BACK = "/app/.logs/backend.jsonl"


def http_get(url, headers=None):
    req = urllib.request.Request(url)
    if headers:
        for k, v in headers.items():
            req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def collector_spans(trace):
    try:
        _, body = http_get(COLLECTOR + "/spans?trace=" + trace)
        data = json.loads(body)
        return data if isinstance(data, list) else []
    except Exception:
        return []


def read_log_lines(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return fh.read().splitlines()
    except Exception:
        return []


def hx(n):
    return "".join(random.choice("0123456789abcdef") for _ in range(n))


failures = []


def fail(msg):
    failures.append(msg)
    print("FAIL:", msg)


def run_scenario(spec, label):
    reqs = spec.get("requests") or []
    if not reqs:
        fail("%s: scenario has no requests" % label)
        return
    for idx, req in enumerate(reqs):
        path = req.get("path")
        exp = req.get("expect_status")
        bspans = req.get("backend_spans")
        exp_err = req.get("expect_error", False)
        if not path:
            fail("%s[req%d]: missing path" % (label, idx))
            continue
        tag = "%s[req%d]" % (label, idx)
        T, P = hx(32), hx(16)

        # 1) drive the frontend with a W3C traceparent for this trace
        status, body = http_get(FRONT + path,
                                headers={"traceparent": "00-%s-%s-01" % (T, P)})
        if status != exp:
            fail("%s: HTTP status %d, expected %d" % (tag, status, exp))

        # 2) collect the spans for this trace (bounded poll for async flush)
        spans = []
        for _ in range(40):
            spans = collector_spans(T)
            if len(spans) >= 1 + (bspans or 0):
                break
            time.sleep(0.2)

        if not spans:
            fail("%s: no spans collected for trace %s" % (tag, T))
        else:
            if any(s.get("trace_id") != T for s in spans):
                fail("%s: a collected span has a foreign trace_id" % tag)
            roots = [s for s in spans if s.get("parent_span_id") == P]
            if len(roots) != 1:
                fail("%s: expected exactly 1 root span (parent=%s), got %d"
                     % (tag, P, len(roots)))
            else:
                root = roots[0]
                if root.get("service") != "frontend":
                    fail("%s: root span service=%r, expected frontend"
                         % (tag, root.get("service")))
                back = [s for s in spans if s.get("service") == "backend"]
                if bspans is not None and len(back) != bspans:
                    fail("%s: expected %d backend spans, got %d"
                         % (tag, bspans, len(back)))
                else:
                    for s in back:
                        if s.get("parent_span_id") != root.get("span_id"):
                            fail("%s: backend span parent != frontend root "
                                 "span id (linkage broken)" % tag)
            if exp_err and not any(s.get("error")
                                   or s.get("status", 0) >= 500
                                   for s in spans):
                fail("%s: expected an error span for the failed request" % tag)

        # 3) structured-log correlation, frontend and backend
        flines = read_log_lines(LOG_FRONT)
        blines = read_log_lines(LOG_BACK)
        goodf = goodb = 0
        bad = []
        for ln in flines + blines:
            if T not in ln:
                continue
            try:
                obj = json.loads(ln)
            except Exception:
                bad.append((ln, "not-valid-json"))
                continue
            if obj.get("trace_id") == T:
                if ln in flines:
                    goodf += 1
                else:
                    goodb += 1
            else:
                bad.append((ln, "trace_id=%r" % (obj.get("trace_id"),)))
        if bad:
            for ln, why in bad[:3]:
                fail("%s: log line referencing trace has %s: %s"
                     % (tag, why, ln[:120]))
        if goodf < 1:
            fail("%s: no valid frontend log line carries trace_id=%s"
                 % (tag, T))
        if goodb < 1:
            fail("%s: no valid backend log line carries trace_id=%s "
                 "(trace not propagated to backend)" % (tag, T))


def discover_scenarios():
    found = []
    for base in ("/tests/visible", "/tests/hidden"):
        if not os.path.isdir(base):
            continue
        for entry in sorted(os.listdir(base)):
            sj = os.path.join(base, entry, "scenario.json")
            if os.path.isfile(sj):
                found.append(sj)
    return found


def main():
    found = discover_scenarios()
    if not found:
        fail("no scenarios found under /tests/visible or /tests/hidden")
    for sj in found:
        try:
            with open(sj, "r", encoding="utf-8") as fh:
                spec = json.load(fh)
        except Exception as exc:
            fail("scenario %s unreadable: %s" % (sj, exc))
            continue
        run_scenario(spec, sj)

    print("scenarios run=%d failures=%d" % (len(found), len(failures)))
    if failures:
        print("--- failures ---")
        for f in failures:
            print("  - " + f)
        sys.exit(1)
    print("ALL SCENARIOS PASSED")
    sys.exit(0)


if __name__ == "__main__":
    main()
