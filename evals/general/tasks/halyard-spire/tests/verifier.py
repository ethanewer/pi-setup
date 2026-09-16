#!/usr/bin/env python3
"""Verifier for halyard-spire.

Runs the whole monitoring pipeline from the agent's deliverables:
  - starts the shipped orders service          (127.0.0.1:8081)
  - starts the agent's exporter                (127.0.0.1:9100)
  - starts Prometheus from the agent's config  (127.0.0.1:9090)
then drives load through the application and asserts, via the Prometheus
HTTP API and a direct decoder probe of the exporter:

  V1  the exporter serves exactly the four required metrics with the correct
      MetricType enums and exact names;
  V2  the counter tracks the application's processed count;
  V3  the gauge tracks the application's pending count;
  V4  the histogram is a native histogram with the declared bucket schema
      (schema 0, 10 positive buckets, bounds through 1024 ms) whose sample
      count and sum match the application's latency window;
  V5  the summary's count and sum match the application's byte counters;
  V6  rate(app_orders_processed_total[1m]) equals the measured processing
      rate (app-counter delta over the same 60s window);
  V7  rate(app_latency_ms[1m]) — a rate expression over the histogram — is a
      histogram whose per-bucket rates sum to the processing rate and are
      non-negative;
  V8  the agent's recording rule produced a queryable series that matches the
      directly-computed rate;
  V9  the agent's three PromQL answers evaluate and agree with independent
      measurements of the same quantities.

Reward is written to /logs/verifier/reward.txt (1 = all pass, 0 = any fail).
"""

import json
import os
import re
import struct
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

APP_URL = "http://127.0.0.1:8081"
EXPORTER_URL = "http://127.0.0.1:9100/metrics"
PROM_URL = "http://127.0.0.1:9090"

failures = []


def fail(msg):
    failures.append(msg)
    print("FAIL: %s" % msg, flush=True)


def check(cond, msg):
    if not cond:
        fail(msg)


def wait_for(fn, timeout, interval=1.0, desc=""):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            v = fn()
            if v:
                return v
            last = None
        except Exception as e:  # noqa: BLE001
            last = e
        time.sleep(interval)
    return last


def app_monitor():
    with urllib.request.urlopen(APP_URL + "/api/monitor", timeout=3) as r:
        return json.loads(r.read().decode())


def prom_query(expr):
    url = PROM_URL + "/api/v1/query?" + urllib.parse.urlencode({"query": expr})
    with urllib.request.urlopen(url, timeout=15) as r:
        data = json.loads(r.read().decode())
    if data.get("status") != "success":
        raise RuntimeError("prom query %r failed: %s" % (expr, data))
    return data["data"]


def prom_num(expr, result_idx=0):
    """Evaluate a PromQL expression, return the numeric value of the first
    result element (scalar or vector value, or histogram mean)."""
    d = prom_query(expr)
    res = d.get("result", [])
    check(expr and len(res) > 0, "promql %r returned no data" % expr)
    if not res:
        return None
    h = res[result_idx].get("histogram")
    if h is not None:
        inner = h[1]
        return float(inner["sum"]) / float(inner["count"]) if float(inner["count"]) else None
    if d.get("resultType") == "scalar":
        return float(res[result_idx][1])
    return float(res[result_idx]["value"][1])


def wait_for_store(expr, timeout):
    """Wait until expr returns a numeric value from the store."""

    def fn():
        d = prom_query(expr)
        res = d.get("result", [])
        if not res:
            return None
        if res[0].get("histogram"):
            if float(res[0]["histogram"][1]["count"]) > 0:
                return True
            return None
        if d.get("resultType") == "scalar":
            return None if res[0][1] == "NaN" else True
        return True

    return wait_for(fn, timeout)


# --------------------------------------------------------------------------
# minimal protobuf decoder for the MetricFamily wire format
# --------------------------------------------------------------------------

def iter_varint(buf, pos):
    shift = 0
    val = 0
    while True:
        if pos >= len(buf):
            raise ValueError("varint overflow")
        b = buf[pos]
        pos += 1
        val |= (b & 0x7F) << shift
        if not (b & 0x80):
            break
        shift += 7
    return val, pos


def fields(buf):
    """Yield (field_number, wire_type, value_bytes_or_int) for a message."""
    pos = 0
    while pos < len(buf):
        key_v, pos = iter_varint(buf, pos)
        field, wt = key_v >> 3, key_v & 7
        if wt == 0:
            v, pos = iter_varint(buf, pos)
            yield field, wt, v
        elif wt == 1:
            if pos + 8 > len(buf):
                raise ValueError("truncated fixed64")
            v = struct.unpack("<d", buf[pos:pos + 8])[0]
            pos += 8
            yield field, wt, v
        elif wt == 2:
            ln, pos = iter_varint(buf, pos)
            yield field, wt, buf[pos:pos + ln]
            pos += ln
        else:
            raise ValueError("unsupported wire type %d" % wt)


def get_sub(value, pos):
    if isinstance(value, bytes):
        return value[pos:] if False else None  # placeholder
    return None


def parse_families(buf):
    """Parse the delimited MetricFamily stream; return list of
    {name, type, metrics:[{counter,gauge,hist_count,hist_sum,zero,counts,
    sum_count,sum_sum}]}."""
    fams = []
    pos = 0
    while pos < len(buf):
        ln, pos = iter_varint(buf, pos)
        msg = buf[pos:pos + ln]
        pos += ln
        fam = {"name": None, "type": None, "metrics": []}
        for f, wt, v in fields(msg):
            if f == 1:
                fam["name"] = v.decode()
            elif f == 3:
                fam["type"] = v
            elif f == 4:
                fam["metrics"].append(_parse_metric(v))
        fams.append(fam)
    return fams


def _parse_metric(msg):
    m = {"labels": {}}
    hist = None
    for f, wt, v in fields(msg):
        if f == 1:
            lf = list(fields(v))
            name = lf[0][2].decode() if lf else "?"
            val = lf[1][2].decode() if len(lf) > 1 else "?"
            m["labels"][name] = val
        elif f == 2:
            for _sf, _sw, _sv in fields(v):
                m["gauge"] = _sv
        elif f == 3:
            for _sf, _sw, _sv in fields(v):
                m["counter"] = _sv
        elif f == 4:
            sd = dict()
            for sf, sw, sv in fields(v):
                sd[sf] = sv
            m["sum_count"] = sd.get(1, 0)
            m["sum_sum"] = sd.get(2, 0.0)
        elif f == 7:
            hist = Hist()
            for sf, sw, sv in fields(v):
                if sf == 1:
                    hist.count = sv
                elif sf == 2:
                    hist.sum = sv
                elif sf == 6:
                    hist.zero_threshold = sv
                elif sf == 7:
                    hist.zero = sv
                elif sf == 12:
                    span = list(fields(sv))
                    hist.span_offset = _zigzag(span[0][2]) if span else 0
                    hist.span_length = span[1][2] if len(span) > 1 else 0
                elif sf == 13:
                    hist.deltas.append(_zigzag(sv))
    if hist is not None:
        m["histogram"] = hist
    return m


def _zigzag(v):
    return (v >> 1) ^ -(v & 1)


class Hist:
    def __init__(self):
        self.count = 0
        self.sum = 0.0
        self.zero_threshold = 1.0
        self.zero = 0
        self.span_offset = 0
        self.span_length = 0
        self.deltas = []

    def positive_counts(self):
        out = []
        acc = self.zero
        for d in self.deltas:
            acc += d
            out.append(acc)
        return out

    def max_bound(self):
        # schema 0: bucket i covers (2^(i-1), 2^i]
        idx = self.span_offset + self.span_length - 1
        return 2 ** idx if self.span_length else None


# --------------------------------------------------------------------------
def run():
    # --- deliverables present ------------------------------------------------
    for p in ("/app/exporter.py", "/app/prometheus.yml",
              "/app/rules.yml", "/app/answers.json"):
        check(os.path.isfile(p), "deliverable missing: %s" % p)
    if not os.path.isfile("/app/app/orders_service.py"):
        check(False, "shipped application missing (broken image)")

    # --- parse the agent's recorded rule names ------------------------------
    rule_names = []
    try:
        text = open("/app/rules.yml").read()
        for m in re.finditer(r"^\s*-\s*record:\s*(\S+)\s*$", text, re.M):
            rule_names.append(m.group(1))
    except Exception as e:  # noqa: BLE001
        check(False, "cannot read /app/rules.yml: %s" % e)
    check(len(rule_names) >= 1, "no recording rule declared in rules.yml")

    # --- start services ------------------------------------------------------
    procs = []
    try:
        procs.append(subprocess.Popen(["python3", "/app/app/orders_service.py"],
                                      stdout=subprocess.DEVNULL,
                                      stderr=subprocess.DEVNULL))
        ok = wait_for(lambda: app_monitor(), timeout=30)
        check(ok is not None, "orders service did not become healthy on 8081")

        procs.append(subprocess.Popen(["python3", "/app/exporter.py"],
                                      stdout=subprocess.DEVNULL,
                                      stderr=subprocess.DEVNULL))
        ok = wait_for(lambda: urllib.request.urlopen(EXPORTER_URL, timeout=2), 30)
        check(ok is not None, "exporter did not serve /metrics on 9100")

        import shutil
        if os.path.isdir("/tmp/verify-prom"):
            shutil.rmtree("/tmp/verify-prom")
        os.makedirs("/tmp/verify-prom", exist_ok=True)
        procs.append(subprocess.Popen(
            ["prometheus",
             "--config.file=/app/prometheus.yml",
             "--storage.tsdb.path=/tmp/verify-prom/store",
             "--enable-feature=native-histograms"],
            cwd="/tmp/verify-prom",
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        ok = wait_for_store("app_orders_processed_total", timeout=120)
        check(ok is not None, "prometheus store never got app_orders_processed_total")

        # ---- V1/V4: exporter source probe (metric types & declared buckets) --
        if ok is not None:
            with urllib.request.urlopen(EXPORTER_URL, timeout=5) as r:
                body = r.read()
            fams = parse_families(body)
            by_name = {f["name"]: f for f in fams}
            check(set(by_name) == {"app_orders_processed_total", "app_orders_pending",
                                   "app_latency_ms", "app_order_bytes"},
                  "metric families: got %s" % sorted(by_name))
            check(by_name["app_orders_processed_total"]["type"] == 0,
                  "app_orders_processed_total type should be counter")
            check(by_name["app_orders_pending"]["type"] == 1,
                  "app_orders_pending type should be gauge")
            check(by_name["app_latency_ms"]["type"] == 4,
                  "app_latency_ms type should be histogram")
            check(by_name["app_order_bytes"]["type"] == 2,
                  "app_order_bytes type should be summary")
            mon = app_monitor()
            c = by_name["app_orders_processed_total"]["metrics"][0]["counter"]
            diff = mon["orders_processed"] - c
            check(0 <= diff <= 6, "counter lag %s out of [0,6]" % diff)
            g = by_name["app_orders_pending"]["metrics"][0]["gauge"]
            check(abs(mon["pending_orders"] - g) <= 8,
                  "gauge %s vs app %s" % (g, mon["pending_orders"]))
            h = by_name["app_latency_ms"]["metrics"][0]["histogram"]
            Hcount = h.count
            mon2 = app_monitor()
            lag = mon2["orders_processed"] - Hcount
            check(0 <= lag <= 6, "histogram sample_count lag %s" % lag)
            check(abs(h.sum - sum(mon2["latency_window"])) <= 2.0,
                  "histogram sum %.3f vs window %.3f" %
                  (h.sum, sum(mon2["latency_window"])))
            check(h.span_offset == 1 and h.span_length == 10,
                  "declared buckets: span offset/length = %d/%d, want 1/10"
                  % (h.span_offset, h.span_length))
            check(h.max_bound() == 1024, "declared buckets max bound %s != 1024"
                  % h.max_bound())
            pc = h.positive_counts()
            check(abs(h.zero + sum(pc) - Hcount) <= 1,
                  "histogram count inconsistency zero=%d pos=%s count=%d"
                  % (h.zero, sum(pc), Hcount))
            s = by_name["app_order_bytes"]["metrics"][0]
            check(abs(s["sum_count"] - mon2["bytes_count"]) <= 6,
                  "summary count %s vs app %s" % (s["sum_count"], mon2["bytes_count"]))
            check(abs(s["sum_sum"] - mon2["bytes_sum"]) <= 3.0,
                  "summary sum %s vs app %s" % (s["sum_sum"], mon2["bytes_sum"]))

        # ---- V6..V9: drive load, then query ---------------------------------
        # Load profile: when hidden cases are present (L1, L2), run exactly
        # ONE load phase with the first case in sorted order (L1). This is a
        # deliberate single-phase design: rate() over the counter/histogram
        # is only well-behaved when the 60 s query window anchors in the
        # idle prefix of the load, which requires a fresh container per run.
        # Chained load phases put stale (but non-zero) histogram samples
        # inside later windows and make rate() over the histogram return
        # garbage. The hidden dir carries alternate load profiles; which one
        # is exercised is decided by the sorted order of the case dirs, so
        # the agent can never predict the load geometry it is judged on.
        hidden = "/tests/hidden"
        profile = {"n": 150, "pace_seconds": 0.17, "urgent_every": 4}
        if os.path.isdir(hidden):
            for case in sorted(os.listdir(hidden)):
                p = os.path.join(hidden, case, "profile.json")
                if os.path.isfile(p):
                    try:
                        profile.update(json.load(open(p)))
                    except Exception:  # noqa: BLE001
                        pass
                    break
        n = int(profile["n"])
        pace = float(profile["pace_seconds"])
        urgent_every = int(profile.get("urgent_every", 4))

        m0 = app_monitor()
        base = m0["orders_processed"]
        for _ in range(n):
            qty = 1 + (_ * 37) % 50
            urgent = (_ % urgent_every) == 0
            body = json.dumps({"sku": "sku-%d" % (_ % 9),
                               "qty": qty, "urgent": urgent}).encode()
            try:
                req = urllib.request.Request(
                    APP_URL + "/orders", data=body,
                    headers={"Content-Type": "application/json"})
                urllib.request.urlopen(req, timeout=5).read()
            except Exception as e:  # noqa: BLE001
                check(False, "order POST failed: %s" % e)
            time.sleep(pace)
        time.sleep(8)  # settle; let scrapes and rule ticks land

        m1 = app_monitor()
        span = 60.0
        R = (m1["orders_processed"] - base) / span

        # V6: rate over the counter
        h1 = prom_num("rate(app_orders_processed_total[1m])")
        check(h1 is not None, "rate() over counter returned nothing")
        if h1 is not None:
            check(abs(h1 - R) <= 0.25 * R + 0.2,
                  "rate()=%.3f vs measured %.3f" % (h1, R))

        # V7: rate() over the histogram
        d = prom_query("rate(app_latency_ms[1m])")
        res = d.get("result", [])
        check(res and res[0].get("histogram") is not None,
              "rate() over histogram did not return a histogram")
        h2sum = 0.0
        ok_rows = False
        if res and res[0].get("histogram"):
            inner = res[0]["histogram"][1]
            for row in inner["buckets"]:
                ok_rows = True
                v = float(row[3])
                h2sum += v
                check(v >= -0.01, "negative bucket rate %s" % v)
            check(ok_rows and len(inner["buckets"]) >= 6,
                  "few buckets in rate histogram: %d" % len(inner["buckets"]))
            check(abs(h2sum - R) <= 0.35 * R + 0.5,
                  "sum of bucket rates %.3f vs measured %.3f" % (h2sum, R))

        # V8: the agent's recording rule
        rec_name = rule_names[0]
        rec_val = prom_num(rec_name)
        check(rec_val is not None, "recording rule series %r not queryable" % rec_name)
        if rec_val is not None:
            check(abs(rec_val - R) <= 0.35 * R + 0.3,
                  "recording rule %.3f vs measured %.3f" % (rec_val, R))
            if h1 is not None:
                check(abs(rec_val - h1) <= 0.35 * R + 0.3,
                      "recording rule %.3f vs rate() %.3f" % (rec_val, h1))

        # V9: the agent's PromQL answers
        try:
            ans = json.load(open("/app/answers.json"))
        except Exception as e:  # noqa: BLE001
            check(False, "answers.json unreadable: %s" % e)
            ans = {}
        for key, ref_fn, tol_fn in (
            ("q1", lambda: R, lambda ref: 0.25 * abs(ref) + 0.2),
            ("q2", lambda: (sum(m1["latency_window"]) / len(m1["latency_window"]))
                 if m1["latency_window"] else 0.0,
             lambda v: max(1.0, 0.12 * abs(v))),
            ("q3", lambda: (m1["bytes_sum"] / m1["bytes_count"])
                 if m1["bytes_count"] else 0.0,
             lambda v: max(0.3, 0.10 * abs(v))),
        ):
            expr = ans.get(key) if isinstance(ans, dict) else None
            if not isinstance(expr, str) or not expr.strip():
                check(False, "answer %s missing/not a string" % key)
                continue
            try:
                got = prom_num(expr)
            except Exception as e:  # noqa: BLE001
                check(False, "answer %s (%r) failed to evaluate: %s"
                      % (key, expr, e))
                continue
            ref = ref_fn()
            check(got is not None and ref is not None,
                  "answer %s: value %s vs reference %s" % (key, got, ref))
            if got is not None and ref is not None:
                tol = tol_fn(ref)
                check(abs(got - ref) <= tol,
                      "answer %s = %.3f, reference %.3f (tol %.2f)"
                      % (key, got, ref, tol))

        # --- store-level existence sanity -------------------------------------
        for name in ("app_orders_processed_total", "app_orders_pending",
                     "app_latency_ms", "app_order_bytes_count",
                     "app_order_bytes_sum"):
            if name.startswith("app_latency"):
                d = prom_query(name)
                present = bool(d.get("result"))
            else:
                present = prom_num(name) is not None
            check(present, "stored series %s not queryable" % name)

    except Exception as e:  # noqa: BLE001
        check(False, "verifier crashed: %r" % e)
    finally:
        for p in procs:
            try:
                p.terminate()
            except Exception:  # noqa: BLE001
                pass
        time.sleep(0.5)
        for p in procs:
            try:
                p.kill()
            except Exception:  # noqa: BLE001
                pass

    if failures:
        print("VERIFIER: %d failure(s)" % len(failures))
        with open("/logs/verifier/reward.txt", "w") as fh:
            fh.write("0\n")
        return 0
    print("VERIFIER: ALL PASS")
    with open("/logs/verifier/reward.txt", "w") as fh:
        fh.write("1\n")
    return 0


if __name__ == "__main__":
    sys.exit(run())