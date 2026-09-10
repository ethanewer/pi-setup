#!/usr/bin/env python3
"""Hidden case H1: LEGACY (old-shape) clients.

Drives the agent's serve.sh-started server with payloads shaped the way v1
clients sent them: a delivery address (field 2), the deprecated
special_instructions field, a weight, and NO packaging oneof. Asserts the
documented receipt semantics: exact echo of every echoed field, the
deprecated field preserved verbatim (no silent drop), packaging_kind 'loose',
and the documented route_code formula.
"""
import os
import socket
import sys
import time

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 50444
sys.path.insert(0, "/app/windlass-dispatch/client")

import grpc  # noqa: E402

import dispatch_pb2 as pb  # noqa: E402
import dispatch_pb2_grpc as svc  # noqa: E402


def slug(addr):
    return addr.strip().lower().replace(" ", "-")


def expected_route(kind, weight, addr):
    wc = "heavy" if weight >= 10000 else "light"
    return "ROUTE:%s:%s:%s" % (kind, wc, slug(addr))


def call(stub, order):
    """RPC with a bounded connection-level retry (server may be cold)."""
    last = None
    for _ in range(60):
        try:
            return stub.SubmitOrder(order, timeout=15)
        except grpc.RpcError as e:
            last = e
            time.sleep(0.5)
    raise last


def legacy_order(tracking, address, instructions, weight):
    o = pb.Order()
    o.tracking_id = tracking
    o.delivery_address = address
    o.special_instructions = instructions
    o.weight_grams = weight
    return o


def main():
    failures = []
    stub = svc.DispatchServiceStub(
        grpc.insecure_channel("127.0.0.1:%d" % PORT))

    # -- legacy request 1: heavy parcel, no oneof, padded address -----------
    addr = "  Victoria Quay 12  "
    instr = "leave at the gatehouse; ring 3x"
    r = call(stub, legacy_order("H1W-0102", addr, instr, 15200))
    checks = [
        ("tracking echo", r.tracking_id, "H1W-0102"),
        ("address echo (exact)", r.delivery_address, addr),
        ("deprecated field preserved (exact)", r.special_instructions, instr),
        ("packaging kind", r.packaging_kind, "loose"),
        ("route code", r.route_code, expected_route("loose", 15200, addr)),
    ]
    for name, got, want in checks:
        if got != want:
            failures.append("H1.1 %s: got %r want %r" % (name, got, want))

    # -- legacy request 2: light, unicode instructions, boundary weight ------
    addr2 = "12 Dock Street"
    instr2 = "fragile: \u26a0 \U0001f69a  a\u030a"
    r2 = call(stub, legacy_order("H1W-0103", addr2, instr2, 9999))
    checks2 = [
        ("deprecated field preserved (unicode)", r2.special_instructions, instr2),
        ("address echo", r2.delivery_address, addr2),
        ("packaging kind", r2.packaging_kind, "loose"),
        ("route code boundary", r2.route_code, expected_route("loose", 9999, addr2)),
    ]
    for name, got, want in checks2:
        if got != want:
            failures.append("H1.2 %s: got %r want %r" % (name, got, want))

    if failures:
        for f in failures:
            print("FAIL", f)
        sys.exit(1)
    print("H1-LEGACY-PASS")


if __name__ == "__main__":
    main()