#!/usr/bin/env python3
"""Independent verifier helpers for the tundra-keystone task.

Written as thin free-standing invariants so they do not depend on how the
oracle implemented the deliverables: any correct solution satisfies them.

Subcommands:
  pipeline <npz> <world_w> <num_layers> <d> <batch>
  async    <json> <n> <cap> <trigger>
  mp       <stdout-file>
"""
import json
import sys

import numpy as np


def check_pipeline(path, world_w, num_layers, d, batch):
    z = np.load(path)
    ok = True
    reasons = []

    def chk(cond, msg):
        nonlocal ok
        if not cond:
            ok = False
            reasons.append(msg)

    chk(int(z["world_size"]) == world_w, "world_size=%s" % z["world_size"])
    chk(int(z["num_layers"]) == num_layers, "num_layers=%s" % z["num_layers"])
    chk(int(z["batch"]) == batch, "batch=%s" % z["batch"])

    part = z["partition"]
    seen = set(part[part >= 0].tolist())
    chk(seen == set(range(num_layers)), "coverage=%s" % sorted(seen))
    chk(len(seen) == num_layers, "duplicate layer ownership")

    for r in range(part.shape[0]):
        row = part[r][part[r] >= 0]
        if len(row) and not np.all(np.diff(row) == 1):
            chk(False, "rank %d not contiguous %s" % (r, row.tolist()))

    chk(bool(np.all(z["bias_sum"] == 0))
        and bool(np.all(z["biases"] == 0)), "bias not zero-initialized")

    chk(z["act_shapes"].shape == (num_layers, 2)
        and np.all(z["act_shapes"] == [batch, d]), "activation shapes wrong")
    chk(z["grad_shapes"].shape == (num_layers, 2)
        and np.all(z["grad_shapes"] == [batch, d]), "gradient shapes wrong")

    acc = z["x0"]
    for i in range(num_layers):
        acc = (acc @ z["weights"][i] + z["biases"][i]).astype(np.float32)
    if num_layers:
        err = float(np.max(np.abs(acc - z["output"])))
        chk(err < 1e-4, "forward recompute err=%.3e" % err)

    return (ok, reasons)


def check_async(path, n, cap, trigger):
    d = json.load(open(path))
    ok = True
    reasons = []

    def chk(cond, msg):
        nonlocal ok
        if not cond:
            ok = False
            reasons.append(msg)

    limit = min(max(int(trigger), 0), n)
    chk(int(d["n"]) == n, "n mismatch")
    chk(int(d["cap"]) == cap, "cap mismatch")
    chk(int(d["max_concurrent"]) <= cap, "concurrency exceeded cap")
    chk(list(d["started"]) == list(range(limit)), "started %s" % d["started"])
    chk(sorted(d["never_started"]) == list(range(limit, n)),
        "never_started %s" % sorted(d["never_started"]))
    chk(sorted(d["completed"]) == list(range(limit)), "completed %s" % d["completed"])
    chk(d["all_accounted"] is True, "job accounting off")
    chk(all(i < limit for i in d["started"]), "queued task leaked into started!")
    return (ok, reasons)


def check_mp(path):
    text = open(path).read()
    ok = True
    reasons = []

    def chk(cond, msg):
        nonlocal ok
        if not cond:
            ok = False
            reasons.append(msg)

    chk(text.count("MP_ENTRY_RUN") == 1, "marker count %d != 1" % text.count("MP_ENTRY_RUN"))
    obj = json.loads(text.strip().splitlines()[-1])
    chk(bool(obj.get("ok")), "mp results wrong")
    chk(len(obj.get("results", [])) == 12, "result count wrong")
    return (ok, reasons)


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    cmd = argv[0]
    if cmd == "pipeline" and len(argv) == 6:
        ok, reasons = check_pipeline(argv[1], int(argv[2]), int(argv[3]),
                                     int(argv[4]), int(argv[5]))
    elif cmd == "async" and len(argv) == 5:
        ok, reasons = check_async(argv[1], int(argv[2]), int(argv[3]), int(argv[4]))
    elif cmd == "mp" and len(argv) == 2:
        ok, reasons = check_mp(argv[1])
    else:
        print("bad args")
        return 2
    print("RESULT", "PASS" if ok else "FAIL")
    for r in reasons:
        print("  -", r)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))