#!/usr/bin/env python3
"""Hidden case H2: NEW-SHAPE clients with the Box arm of the packaging oneof
already set, plus the deprecated field. Asserts exact echo semantics, oneof
derived packaging_kind/route_code, and the heavy/light boundary at
weight_grams == 10000.
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


def box_order(tracking, address, instructions, weight, w, h, d):
    o = pb.Order()
    o.tracking_id = tracking
    o.delivery_address = address
    o.special_instructions = instructions
    o.weight_grams = weight
    o.box.width_mm = w
    o.box.height_mm = h
    o.box.depth_mm = d
    return o


def route_for(kind, weight, addr):
    wc = "heavy" if weight >= 10000 else "light"
    return "ROUTE:%s:%s:%s" % (kind, wc, slug(addr))


def main():
    failures = []
    stub = svc.DispatchServiceStub(
        grpc.insecure_channel("127.0.0.1:%d" % PORT))

    # -- box request 1: heavy box, emoji instructions ------------------------
    addr = "Cedar Wharf, Unit 4"
    instr = "FRAGILE \U0001f69a GLASS"
    r = call(stub, box_order("H2B-0077", addr, instr, 10050, 410, 310, 260))
    want_route = route_for("box410-310-260", 10050, addr)
    checks = [
        ("tracking echo", r.tracking_id, "H2B-0077"),
        ("address echo", r.delivery_address, addr),
        ("deprecated preserved (emoji)", r.special_instructions, instr),
        ("packaging kind", r.packaging_kind, "box"),
        ("route box", r.route_code, want_route),
    ]
    for name, got, want in checks:
        if got != want:
            failures.append("H2.1 %s: got %r want %r" % (name, got, want))

    # -- box request 2: weight exactly at the heavy boundary -----------------
    addr2 = "5 Windlass Reach"
    instr2 = " pad me "  # leading/trailing spaces must round-trip exactly
    r2 = call(stub, box_order("H2B-0078", addr2, instr2, 10000, 150, 150, 150))
    checks2 = [
        ("deprecated preserved (spaces)", r2.special_instructions, instr2),
        ("address echo", r2.delivery_address, addr2),
        ("packaging kind", r2.packaging_kind, "box"),
        ("route boundary=heavy", r2.route_code, route_for("box150-150-150", 10000, addr2)),
    ]
    for name, got, want in checks2:
        if got != want:
            failures.append("H2.2 %s: got %r want %r" % (name, got, want))

    if failures:
        for f in failures:
            print("FAIL", f)
        sys.exit(1)
    print("H2-BOX-PASS")


if __name__ == "__main__":
    main()