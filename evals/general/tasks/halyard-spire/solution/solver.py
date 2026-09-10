#!/usr/bin/env python3
"""Oracle solver for halyard-spire.

Writes the four deliverables into /app:

  /app/exporter.py      - Prometheus exporter for the shipped orders service
  /app/prometheus.yml   - Prometheus server config incl. the scrape job
  /app/rules.yml        - recording rules (PromQL -> recorded series)
  /app/answers.json     - answers to the three questions, as PromQL

The exporter consumes the service's /api/monitor JSON and serves the
delimited-protobuf MetricFamily wire format documented in /app/docs/wire.md
(same checks the verifier applies: exact metric names, exact types, exact
bucket schema). Nothing here reads /tests; every number is derived from the
public, documented contracts of the shipped app and the wire format.
"""

import json
import pathlib

APP = pathlib.Path("/app")

# --- metric contract: names, types, bucket bounds -------------------------
COUNTER_NAME = "app_orders_processed_total"
GAUGE_NAME = "app_orders_pending"
HIST_NAME = "app_latency_ms"
SUMMARY_NAME = "app_order_bytes"

# Upper bounds (inclusive) of the declared latency buckets, schema 0.
BUCKET_BOUNDS = [1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024]
# Interval (b[i-1], b[i]] has count[i]; b[0] == 1 covers (0, 1].

EXPORTER = r'''#!/usr/bin/env python3
"""Prometheus exporter for the orders service (halyard-spire).

Polls http://127.0.0.1:8081/api/monitor and serves the four application
metrics over the delimited-protobuf MetricFamily wire format (see
/app/docs/wire.md). All protocol details are specific to the Prometheus on
this image: native histograms must arrive as protobuf or they are not
recorded as histograms at all.

Run: python3 /app/exporter.py      (binds 127.0.0.1:9100)
"""

import http.server
import json
import struct
import threading
import time
import urllib.request

APP_URL = "http://127.0.0.1:8081/api/monitor"
HOST, PORT = "127.0.0.1", 9100
POLL_SECONDS = 0.15
STALE_SECONDS = 2.0

BUCKET_BOUNDS = %(bounds)r          # ms, inclusive upper bounds, schema 0


def varint(n):
    n &= (1 << 64) - 1  # unsigned 64-bit wrap
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def key(field, wire):
    return varint((field << 3) | wire)


def v_msg(field, payload):
    return key(field, 2) + varint(len(payload)) + payload


def v_str(field, s):
    return v_msg(field, s.encode("utf-8"))


def v_dbl(field, x):
    return key(field, 1) + struct.pack("<d", float(x))


def v_uint(field, n):
    return key(field, 0) + varint(int(n))


def v_sint(field, n):
    z = (int(n) << 1) ^ (int(n) >> 63)
    return key(field, 0) + varint(z)


def family(name, help_text, mtype, metric_payloads):
    out = v_str(1, name) + v_str(2, help_text) + v_uint(3, mtype)
    out += b"".join(metric_payloads)
    return out


def metric_value(mtype, value):
    """value: (counter_value | gauge_value)"""
    if mtype in (0, 1, 3):
        return v_dbl(1, value)
    raise ValueError("metric_value can only encode scalar types")


def summary_value(count, total):
    return v_uint(1, count) + v_dbl(2, total)


def histogram_value(samples):
    """samples: iterable of latencies (ms). Returns the sparse Histogram
    message payload for schema 0 with the declared bucket bounds."""
    counts = [0] * len(BUCKET_BOUNDS)   # bucket i covers (b[i-1], b[i]];
    zero = 0                            # b[0] = 1 => (0, 1] is the zero bucket
    total = 0.0
    for s in samples:
        total += s
        if s <= BUCKET_BOUNDS[0]:
            zero += 1
            continue
        # first bound strictly greater than s => its bucket
        lo = 0
        for i, b in enumerate(BUCKET_BOUNDS):
            if s <= b:
                lo = i
                break
        counts[lo] += 1
    out = b""
    out += v_uint(1, zero + sum(counts))       # sample_count
    out += v_dbl(2, total)                   # sample_sum
    out += v_sint(5, 0)                       # schema 0
    out += v_dbl(6, float(BUCKET_BOUNDS[0]))  # zero_threshold
    out += v_uint(7, zero)                    # zero_count
    # positive buckets: bounds (1,2],(2,4],...; first index at 2^1
    pos = counts[1:] if len(counts) > 1 else []
    out += v_msg(12, v_sint(1, 1) + v_uint(2, len(pos)))  # one span
    prev = zero
    for c in pos:
        out += key(13, 0) + varint(((c - prev) << 1) ^ ((c - prev) >> 63))
        prev = c
    return out


def metric_msg(labels, mtype, payload):
    out = b""
    for k, val in labels.items():
        out += v_str(1, str(k)) + v_str(2, str(val))
    if mtype == 4:      # HISTOGRAM
        out += v_msg(7, payload)
    elif mtype == 2:    # SUMMARY
        out += v_msg(4, payload)
    else:
        out += v_msg({0: 3, 1: 2, 3: 5}[mtype], payload)
    return v_msg(4, out)


def frame(mf):
    return varint(len(mf)) + mf


STATE = {"monitor": None, "ts": 0.0, "lock": threading.Lock()}


def poll():
    while True:
        try:
            with urllib.request.urlopen(APP_URL, timeout=0.5) as r:
                data = json.loads(r.read().decode("utf-8"))
            with STATE["lock"]:
                STATE["monitor"] = data
                STATE["ts"] = time.time()
        except Exception:
            pass
        time.sleep(POLL_SECONDS)


def serve_body():
    with STATE["lock"]:
        mon = STATE["monitor"]
        ts = STATE["ts"]
    if mon is None or time.time() - ts > STALE_SECONDS:
        mon = {}
    processed = mon.get("orders_processed", 0)
    pending = mon.get("pending_orders", 0)
    window = mon.get("latency_window", [])
    bcount = mon.get("bytes_count", 0)
    bsum = mon.get("bytes_sum", 0.0)

    body = b""
    # 1) counter
    body += frame(family("app_orders_processed_total",
                         "Orders processed since service start", 0,
                         [metric_msg({}, 0, metric_value(0, processed))]))
    # 2) gauge
    body += frame(family("app_orders_pending",
                         "Orders currently inside the service", 1,
                         [metric_msg({}, 1, metric_value(1, pending))]))
    # 3) histogram with declared buckets
    body += frame(family("app_latency_ms",
                         "Order latency in milliseconds", 4,
                         [metric_msg({}, 4, histogram_value(window))]))
    # 4) summary
    body += frame(family("app_order_bytes",
                         "Order payload size in bytes", 2,
                         [metric_msg({}, 2, summary_value(bcount, bsum))]))
    return body


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/metrics":
            self.send_response(404)
            self.end_headers()
            return
        body = serve_body()
        self.send_response(200)
        self.send_header(
            "Content-Type",
            "application/vnd.google.protobuf;"
            "proto=io.prometheus.client.MetricFamily;encoding=delimited",
        )
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    threading.Thread(target=poll, daemon=True).start()
    http.server.ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
''' % {"bounds": BUCKET_BOUNDS}

PROMETHEUS_YML = """# Prometheus server configuration for the orders service.
# The verifier runs: prometheus --config.file=/app/prometheus.yml
#   --storage.tsdb.path=/tmp/verify-prom --enable-feature=native-histograms
global:
  scrape_interval: 5s
  evaluation_interval: 2s

rule_files:
  - /app/rules.yml

scrape_configs:
  - job_name: orders
    scrape_interval: 1s
    metrics_path: /metrics
    static_configs:
      - targets: ["127.0.0.1:9100"]
        labels:
          app: orders
"""

RULES_YML = """# Recording rules for the orders service.
#
# The recorded series below materialises the per-second processing rate as a
# queryable metric, so dashboards never need to run rate() themselves.
groups:
  - name: orders_rates
    interval: 2s
    rules:
      - record: app_orders_rate_per_second
        expr: "rate(app_orders_processed_total[1m])"
        labels:
          metric: derived
          source: recording-rule
      - record: app_pending_window_average
        expr: "avg_over_time(app_orders_pending[1m])"
        labels:
          metric: derived
          source: recording-rule
"""

ANSWERS = {
    "q1": "rate(app_orders_processed_total[1m])",
    "q2": "app_latency_ms",
    "q3": "app_order_bytes_sum / app_order_bytes_count",
}


def main():
    APP.mkdir(exist_ok=True)
    (APP / "exporter.py").write_text(EXPORTER)
    (APP / "prometheus.yml").write_text(PROMETHEUS_YML)
    (APP / "rules.yml").write_text(RULES_YML)
    (APP / "answers.json").write_text(json.dumps(ANSWERS, indent=2) + "\n")
    print("wrote /app/exporter.py /app/prometheus.yml /app/rules.yml /app/answers.json")


if __name__ == "__main__":
    main()