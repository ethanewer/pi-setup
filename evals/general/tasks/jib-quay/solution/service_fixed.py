#!/usr/bin/env python3
"""quay-hub — an FX transfer hub service (shipped with a seeded concurrency defect).

A minimal line-protocol TCP service bound to 127.0.0.1 (loopback only).
One request per line, ASCII, LF-terminated:

    TRANSFER <src> <dst> <cents>      move <cents> from <src> to <dst>,
                                      converting via the live rate table;
                                      response "OK <converted>" on success,
                                      "NOACCT" for unknown accounts, "NOFUNDS"
                                      for insufficient funds, "BAD" for a
                                      malformed amount or src == dst
    BALANCE <account>                 response "OK <balance_cents>" or "NOACCT"
    JOURNAL                           response "OK <json-line>" — the ordered
                                      list of applied transfers
    STOP                              response "BYE", then the process exits

The ledger (--ledger) is a JSON file:

    {
      "accounts": {"<id>": {"balance_cents": <int>, "currency": "<CCY>"}, ...},
      "rates":    {"<CCY>-<CCY>": <float>, ...}
    }

A transfer of <cents> from <src> to <dst> is applied as: the source account
is debited <cents> in its own currency, the destination account is credited
round(<cents> * rate(src.currency, dst.currency)) in its own currency, where
rate() looks up "<CCY>-<CCY>" in the rate table and defaults to 1.0 when the
pair is absent.  Every applied transfer is appended to the in-memory journal
as {"src": ..., "dst": ..., "cents": ..., "converted": ...}.  The reported
balance of an account is always its current balance_cents.
"""
import argparse
import json
import socket
import sys
import threading
import time


class TransferHub:
    """Shared ledger state with one lock per account plus a journal lock."""

    def __init__(self, ledger_path, latency=0.02):
        with open(ledger_path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        self.accounts = {}
        self.account_locks = {}
        for aid, spec in data["accounts"].items():
            self.accounts[aid] = {
                "balance_cents": int(spec["balance_cents"]),
                "currency": str(spec["currency"]),
            }
            self.account_locks[aid] = threading.Lock()
        self.rates = {k: float(v) for k, v in data.get("rates", {}).items()}
        self.journal = []
        self.journal_lock = threading.Lock()
        self.latency = float(latency)
        self._stop = False

    # ------------------------------------------------------------------
    # protocol
    # ------------------------------------------------------------------
    def rate_for(self, src_currency, dst_currency):
        return self.rates.get("%s-%s" % (src_currency, dst_currency), 1.0)

    def apply_transfer(self, src, dst, cents):
        if src not in self.accounts or dst not in self.accounts:
            return "NOACCT"
        # Every transfer acquires its two account locks in ONE canonical
        # order (accounts sorted by identifier), so two transfers that touch
        # the same pair can never wait on each other's locks in opposite
        # orders.  The accounting still debits src and credits dst.
        first, second = sorted((src, dst))
        first_lock = self.account_locks[first]
        second_lock = self.account_locks[second]
        with first_lock:
            with second_lock:
                balance = self.accounts[src]["balance_cents"]
                if balance < cents:
                    return "NOFUNDS"
                # The conversion rate is read from the (live) rate table after
                # a momentary back-pressure step.  Both accounts stay reserved
                # across that step so the conversion applies atomically.
                time.sleep(self.latency)
                rate = self.rate_for(self.accounts[src]["currency"],
                                     self.accounts[dst]["currency"])
                converted = int(round(cents * rate))
                if converted <= 0:
                    return "BAD"
                self.accounts[src]["balance_cents"] = balance - cents
                self.accounts[dst]["balance_cents"] += converted
                with self.journal_lock:
                    self.journal.append({
                        "src": src,
                        "dst": dst,
                        "cents": cents,
                        "converted": converted,
                    })
        return "OK %d" % converted

    def handle_line(self, line):
        parts = line.split()
        if not parts:
            return "BAD"
        cmd = parts[0]
        if cmd == "TRANSFER" and len(parts) == 4:
            src, dst, amt = parts[1], parts[2], parts[3]
            if src == dst:
                return "BAD"
            try:
                cents = int(amt)
            except ValueError:
                return "BAD"
            if cents <= 0:
                return "BAD"
            return self.apply_transfer(src, dst, cents)
        if cmd == "BALANCE" and len(parts) == 2:
            aid = parts[1]
            if aid not in self.accounts:
                return "NOACCT"
            with self.account_locks[aid]:
                return "OK %d" % self.accounts[aid]["balance_cents"]
        if cmd == "JOURNAL" and len(parts) == 1:
            with self.journal_lock:
                return "OK " + json.dumps(self.journal)
        if cmd == "STOP" and len(parts) == 1:
            self._stop = True
            return "BYE"
        return "BAD"

    # ------------------------------------------------------------------
    # socket plumbing
    # ------------------------------------------------------------------
    def serve_connection(self, conn):
        try:
            buf = b""
            while not self._stop:
                chunk = conn.recv(65536)
                if not chunk:
                    break
                buf += chunk
                while b"\n" in buf:
                    line, _, buf = buf.partition(b"\n")
                    line = line.decode("ascii", "replace").strip()
                    if not line:
                        continue
                    resp = self.handle_line(line)
                    conn.sendall(resp.encode("ascii") + b"\n")
                    if self._stop:
                        return
        except OSError:
            pass
        finally:
            try:
                conn.close()
            except OSError:
                pass


def main(argv):
    parser = argparse.ArgumentParser(
        prog="service.py",
        description="quay-hub FX transfer service (loopback only)")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ledger", required=True)
    parser.add_argument("--latency", type=float, default=0.02,
                        help="simulated FX rate-feed latency per transfer (s)")
    args = parser.parse_args(argv)

    hub = TransferHub(args.ledger, args.latency)

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", args.port))
    srv.listen(64)
    srv.settimeout(0.5)
    try:
        print("READY", flush=True)
        while not hub._stop:
            try:
                conn, _ = srv.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            t = threading.Thread(target=hub.serve_connection,
                                 args=(conn,), daemon=True)
            t.start()
    finally:
        srv.close()
    time.sleep(0.2)  # let the STOP reply flush before the process exits
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))