#!/usr/bin/env python3
"""driver.py — deterministic concurrent load driver for the quay-hub service.

Runs the transfer hub (/app/service.py by default) against a ledger and an
operation mix, drives the mix through N concurrent client connections (or a
single connection with --serial), watches for stalls, and writes a JSON
report to --out.  This is the harness you use to reproduce the shipped
service's defect and to check a repair; the grader drives its own harness
against its own hidden mixes, but the semantics are identical.

Mix format (--mix):

    {
      "workers": 3,
      "ops": [
        {"op": "transfer", "src": "alice", "dst": "bob", "cents": 12000},
        ...
      ]
    }

Worker w is assigned ops[w::len:workers] (round-robin); with --serial a
single worker sends every op in list order.  All workers start at a barrier,
so the first ops of all workers hit the service at (near) the same instant.

OUT.json on completion:

    {
      "ok": true,
      "stall": false,
      "elapsed": <seconds from barrier to last response>,
      "responses": [[op_index, "response"], ...],
      "journal": [{"src":.., "dst":.., "cents":.., "converted":..}, ...],
      "balances": {"<account>": <int>, ...} | null
    }

A stalled run writes ok=false, stall=true and exits 1.
"""
import argparse
import json
import socket
import subprocess
import sys
import threading
import time


class WorkerClients:
    """Spawns `workers` client threads; each sends its op stream to the hub."""

    def __init__(self, port, streams, gap, deadline):
        self.port = port
        self.streams = streams
        self.gap = gap
        self.deadline = deadline
        self.results = []          # (worker_idx, op_index, response)
        self.result_lock = threading.Lock()
        self.stall = threading.Event()
        self.last_response_at = [0.0]

    def _worker(self, widx, ops):
        try:
            sock = socket.create_connection(("127.0.0.1", self.port),
                                            timeout=self.deadline)
        except OSError:
            self.stall.set()
            return
        try:
            for op_index, op in enumerate(ops):
                line = "TRANSFER %s %s %d" % (op["src"], op["dst"], op["cents"])
                try:
                    sock.sendall(line.encode("ascii") + b"\n")
                except OSError:
                    self.stall.set()
                    return
                data = b""
                while not data.endswith(b"\n"):
                    try:
                        chunk = sock.recv(4096)
                    except socket.timeout:
                        self.stall.set()
                        return
                    if not chunk:
                        self.stall.set()
                        return
                    data += chunk
                resp = data.decode("ascii", "replace").strip()
                with self.result_lock:
                    self.results.append((widx, op_index, resp))
                    self.last_response_at[0] = time.monotonic()
        finally:
            try:
                sock.close()
            except OSError:
                pass

    def run(self, mix):
        """Drive the mix; returns (ok, elapsed, responses)."""
        t0 = time.monotonic()
        threads = [threading.Thread(target=self._worker, args=(w, stream))
                   for w, stream in enumerate(self.streams)]
        for t in threads:
            t.start()
        deadline_at = t0 + self.deadline
        while not self.stall.is_set():
            now = time.monotonic()
            if now >= deadline_at:
                self.stall.set()
                break
            with self.result_lock:
                got = len(self.results)
                last = self.last_response_at[0] or t0
            if got >= len(mix["ops"]):
                break
            if (now - last) > self.gap:
                self.stall.set()
                break
            time.sleep(0.02)
        for t in threads:
            t.join(timeout=1.0)
        with self.result_lock:
            responses = sorted(self.results)
            elapsed = (self.last_response_at[0] - t0) if self.last_response_at[0] else 0.0
        ok = (not self.stall.is_set()) and len(responses) == len(mix["ops"])
        return ok, elapsed, responses


def fetch_control(port, accounts, recv_timeout=2.0):
    """On one control connection: BALANCEs, JOURNAL, then STOP.

    Returns (balances, journal, stopped_cleanly).  The service answers per
    connection in order and exits after BYE, so STOP must be the last request.
    A deadlocked service can hang individual responses; recv_timeout bounds
    each of them.
    """
    balances = {}
    journal = None
    stopped = False
    try:
        sock = socket.create_connection(("127.0.0.1", port), timeout=5)
        sock.settimeout(recv_timeout)
    except OSError:
        return None, None, False

    def req(line):
        sock.sendall(line.encode("ascii") + b"\n")
        data = b""
        while not data.endswith(b"\n"):
            chunk = sock.recv(65536)
            if not chunk:
                raise EOFError
            data += chunk
        return data.decode("ascii", "replace").strip()

    try:
        for aid in accounts:
            r = req("BALANCE %s" % aid)
            balances[aid] = int(r[3:]) if r.startswith("OK ") else None
        rj = req("JOURNAL")
        if rj.startswith("OK "):
            try:
                journal = json.loads(rj[3:])
            except ValueError:
                journal = None
        r = req("STOP")
        stopped = (r == "BYE")
    except (OSError, EOFError):
        stopped = False
    finally:
        try:
            sock.close()
        except OSError:
            pass
    return balances, journal, stopped


def run_mix(args, mix):
    streams = [[] for _ in range(mix.get("workers", 1))]
    for i, op in enumerate(mix["ops"]):
        if args.serial:
            streams[0].append(op)
        else:
            streams[i % len(streams)].append(op)
    if args.serial:
        streams = [streams[0]]

    svc_cmd = [
        sys.executable, args.service,
        "--port", str(args.port),
        "--ledger", args.ledger,
        "--latency", str(args.latency),
    ]
    proc = subprocess.Popen(svc_cmd, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True)
    try:
        line = proc.stdout.readline() if proc.stdout else ""
        if not line.startswith("READY"):
            print("driver: service did not print READY in time", file=sys.stderr)
            return None
        clients = WorkerClients(args.port, streams, args.gap, args.deadline)
        ok, elapsed, responses = clients.run(mix)
        balances = journal = None
        stopped = False
        if ok:
            balances, journal, stopped = fetch_control(args.port, args.accounts)
        return {
            "ok": ok and stopped,
            "stall": not ok,
            "elapsed": round(elapsed, 4),
            "responses": responses,
            "journal": journal,
            "balances": balances if ok else None,
        }
    finally:
        try:
            proc.terminate()
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()


def main(argv):
    ap = argparse.ArgumentParser(prog="driver.py")
    ap.add_argument("--service", default="/app/service.py")
    ap.add_argument("--ledger", default="/app/ledger.json")
    ap.add_argument("--mix", default="/app/mix_visible.json")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--latency", type=float, default=0.02)
    ap.add_argument("--serial", action="store_true",
                    help="send every op on one connection, in list order")
    ap.add_argument("--gap", type=float, default=2.0,
                    help="seconds without a response that count as a stall")
    ap.add_argument("--deadline", type=float, default=120.0)
    ap.add_argument("--out", default="/tmp/driver_out.json")
    args = ap.parse_args(argv)

    with open(args.mix, "r", encoding="utf-8") as fh:
        mix = json.load(fh)
    with open(args.ledger, "r", encoding="utf-8") as fh:
        args.accounts = list(json.load(fh)["accounts"].keys())

    report = run_mix(args, mix)
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(report if report is not None else
                  {"ok": False, "stall": True, "responses": [],
                   "journal": None, "balances": None, "elapsed": 0.0}, fh)
    if report is None or not report["ok"]:
        print("driver: STALL / failure (see %s)" % args.out, file=sys.stderr)
        return 1
    print("driver: completed %d ops in %.3fs (see %s)" %
          (len(mix["ops"]), report["elapsed"], args.out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))