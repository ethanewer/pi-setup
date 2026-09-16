#!/usr/bin/env python3
"""Hidden case H3: NEW-SHAPE clients with the Envelope arm of the packaging
oneof, plus the Ping RPC added in v2. Covers the envelope branch, zero/light
weights, an empty deprecated field (must not gain injected content), and the
second RPC path.
"""
import sys
import time

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 50444
sys.path.insert(0, "/app/windlass-dispatch/client")

import grpc  # noqa: E402

import dispatch_pb2 as pb  # noqa: E402
import dispatch_pb2_grpc as svc  # noqa: E402


def slug(addr):
    return addr.strip().lower().replace(" ", "-")


def call(stub, order):
    last = None
    for _ in range(60):
        try:
            return stub.SubmitOrder(order, timeout=15)
        except grpc.RpcError as e:
            last = e
            time.sleep(0.5)
    raise last


def env_order(tracking, address, instructions, weight, t):
    o = pb.Order()
    o.tracking_id = tracking
    o.delivery_address = address
    o.special_instructions = instructions
    o.weight_grams = weight
    o.envelope.thickness_mm = t
    return o


def route_for(kind, weight, addr):
    wc = "heavy" if weight >= 10000 else "light"
    return "ROUTE:%s:%s:%s" % (kind, wc, slug(addr))


def main():
    failures = []
    stub = svc.DispatchServiceStub(
        grpc.insecure_channel("127.0.0.1:%d" % PORT))

    # -- envelope request 1: zero weight, empty deprecated field --------------
    addr = "99 Lighthouse Road"
    r = call(stub, env_order("H3E-3301", addr, "", 0, 7))
    checks = [
        ("tracking echo", r.tracking_id, "H3E-3301"),
        ("address echo", r.delivery_address, addr),
        ("empty deprecated stays empty", r.special_instructions, ""),
        ("packaging kind", r.packaging_kind, "envelope"),
        ("route env light", r.route_code, route_for("env7", 0, addr)),
    ]
    for name, got, want in checks:
        if got != want:
            failures.append("H3.1 %s: got %r want %r" % (name, got, want))

    # -- envelope request 2: heavy envelope, plain instructions ---------------
    addr2 = "8 Mooring Lane"
    r2 = call(stub, env_order("H3E-3302", addr2, "PERSONAL", 20000, 25))
    checks2 = [
        ("deprecated preserved", r2.special_instructions, "PERSONAL"),
        ("address echo", r2.delivery_address, addr2),
        ("packaging kind", r2.packaging_kind, "envelope"),
        ("route env heavy", r2.route_code, route_for("env25", 20000, addr2)),
    ]
    for name, got, want in checks2:
        if got != want:
            failures.append("H3.2 %s: got %r want %r" % (name, got, want))

    # -- v2-added Ping RPC (with retry) --------------------------------------
    pong = None
    for _ in range(60):
        try:
            pong = stub.Ping(pb.PingRequest(nonce="h3"), timeout=15)
            break
        except grpc.RpcError as e:
            last = e
            time.sleep(0.5)
    if pong is None or pong.nonce != "h3":
        failures.append("H3.3 ping: nonce not echoed (got %r)" % (pong.nonce if pong else None))

    if failures:
        for f in failures:
            print("FAIL", f)
        sys.exit(1)
    print("H3-ENVELOPE-PASS")


if __name__ == "__main__":
    main()