#!/usr/bin/env python3
"""OrdersService: a deliberately small order-processing HTTP service.

This is the *shipped application* for the halyard-spire task. It listens on
127.0.0.1:8081 and answers three endpoints:

  POST /orders
      Body: {"sku": str, "qty": int, "urgent": bool}
      Places an order. The service "processes" it (a small proportional
      pause), then records the order latency and payload size into its
      metrics state. Returns {"order_id": int, "latency_ms": float}.

  GET /status
      Human-readable one-liner with current counters.

  GET /api/monitor
      Machine-readable snapshot of the metrics state. The metrics exporter
      built as part of the task consumes this endpoint. Shape:

      {
        "orders_processed": int,     # completed orders since start
        "orders_failed": int,        # orders that failed validation
        "orders_rejected": int,      # orders rejected during processing
        "pending_orders": int,       # orders currently inside the service
        "latency_window": [float...],# latencies of recent completed orders
        "latency_capacity": int,     # window size (first-in-first-out)
        "bytes_count": int,          # total number of payloads accepted
        "bytes_sum": float           # total payload bytes accepted
      }

The service is single-threaded order *acceptance* with a small thread pool
for processing, so pending_orders can be observed to rise while traffic is
slow. Latency is dominated by (qty * 2.5ms) plus a per-urgency term, plus a
small deterministic jitter derived from the order id so the distribution is
stable once the sample count is large enough.
"""

import json
import math
import random
import threading
import time
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "127.0.0.1"
PORT = 8081

LATENCY_CAPACITY = 4000  # how many recent latencies the window keeps
SAMPLE_WINDOW_S = 75.0   # max age of samples kept (seconds)


class State:
    """The application's metrics state; the /api/monitor endpoint is its
    read-only projection. All updates are done under GIL-safe monostate
    with simple locks so concurrent requests never corrupt counts."""

    def __init__(self):
        self.lock = threading.Lock()
        self.orders_processed = 0
        self.orders_failed = 0
        self.orders_rejected = 0
        self.pending_orders = 0
        self.latency_window = deque()  # (ts, latency_ms)
        self.bytes_count = 0
        self.bytes_sum = 0.0
        self.next_order_id = 1000

    def snapshot(self):
        now = time.time()
        with self.lock:
            # prune expired latency samples
            keep = deque()
            for ts, lat in self.latency_window:
                if now - ts <= SAMPLE_WINDOW_S:
                    keep.append((ts, lat))
            self.latency_window = keep
            return {
                "orders_processed": self.orders_processed,
                "orders_failed": self.orders_failed,
                "orders_rejected": self.orders_rejected,
                "pending_orders": self.pending_orders,
                "latency_window": [lat for _, lat in keep],
                "latency_capacity": LATENCY_CAPACITY,
                "bytes_count": self.bytes_count,
                "bytes_sum": round(self.bytes_sum, 3),
            }

    def accept(self, order_id, payload_len):
        with self.lock:
            self.pending_orders += 1
            self.bytes_count += 1
            self.bytes_sum += payload_len
            start_order = self.next_order_id
            self.next_order_id = order_id + 1
        return start_order

    def complete(self, latency_ms):
        now = time.time()
        with self.lock:
            self.orders_processed += 1
            self.pending_orders = max(0, self.pending_orders - 1)
            self.latency_window.append((now, latency_ms))
            if len(self.latency_window) > LATENCY_CAPACITY:
                self.latency_window.popleft()

    def fail(self):
        with self.lock:
            self.orders_failed += 1
            self.pending_orders = max(0, self.pending_orders - 1)

    def reject(self):
        with self.lock:
            self.orders_rejected += 1


STATE = State()


def process_order(order_id, sku, qty, urgent):
    """Run 'off the accept path': simulate processing cost, then record the
    latency and complete the order."""
    base = max(0.5, qty * 2.5)
    urgency = 18.0 if urgent else 4.0
    jitter = 1.0 + math.sin(order_id * 0.713) * 0.9  # deterministic in [-0.9, 1.9]
    latency_ms = base * (1.0 + urgency / 100.0) + jitter
    time.sleep(latency_ms / 1000.0)
    STATE.complete(latency_ms)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send(self, code, payload, ctype="application/json"):
        body = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path != "/orders":
            self._send(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(length)
        except Exception:
            raw = b"{}"
        try:
            body = json.loads(raw.decode("utf-8"))
            sku = str(body.get("sku", "unknown"))
            qty = int(body.get("qty", 1))
            urgent = bool(body.get("urgent", False))
            if not (0 < qty <= 50):
                raise ValueError("qty out of range")
        except Exception:
            STATE.fail()
            self._send(400, {"error": "invalid order"})
            return

        with STATE.lock:
            order_id = STATE.next_order_id
            STATE.next_order_id += 1
        STATE.accept(order_id, float(len(raw)))
        threading.Thread(
            target=process_order, args=(order_id, sku, qty, urgent), daemon=True
        ).start()
        self._send(202, {"order_id": order_id})

    def do_GET(self):
        if self.path == "/status":
            s = STATE.snapshot()
            msg = (
                "orders=%d failed=%d rejected=%d pending=%d bytes=%d"
                % (
                    s["orders_processed"],
                    s["orders_failed"],
                    s["orders_rejected"],
                    s["pending_orders"],
                    int(s["bytes_sum"]),
                )
            )
            self._send(200, {"status": msg}, "text/plain")
        elif self.path == "/api/monitor":
            self._send(200, STATE.snapshot())
        else:
            self._send(404, {"error": "not found"})

    def log_message(self, *args):
        pass


def main():
    srv = ThreadingHTTPServer((HOST, PORT), Handler)
    print("orders service listening on %s:%d" % (HOST, PORT), flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()