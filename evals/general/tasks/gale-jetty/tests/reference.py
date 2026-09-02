#!/usr/bin/env python3
"""Independent re-derivation of every expected output for gale-jetty.

This is the verifier's OWN reference math — written separately from the agent's
deliverable programs so a solution that hard-codes or mis-generalizes fails when
run on hidden scenarios with different numbers. It takes an input (scenario)
directory and returns a dict of expected results computed from the raw fixtures.
"""
import csv
import json
import os

import numpy as np

__all__ = ["expected", "snapshot_classes", "ITERATIONS"]


def _iterations():
    p = "/app/compute_seq.py"
    ns = {}
    if os.path.exists(p):
        with open(p) as fh:
            code = fh.read()
        # evaluate only the ITERATIONS assignment
        for line in code.splitlines():
            if line.strip().startswith("ITERATIONS"):
                exec(line, ns)
    return int(ns.get("ITERATIONS", 23))


ITERATIONS = _iterations()


def _load_config(indir):
    cfg = {"grid": {"rows": 8, "cols": 10}, "close": {"target": 50.0, "tolerance": 25.0}}
    p = os.path.join(indir, "config.json")
    if os.path.exists(p):
        try:
            cfg.update(json.load(open(p)))
        except Exception:
            pass
    return cfg


def snapshot_classes(indir):
    """Expected {bucket: [filenames]} from the raw inbox before it is moved."""
    inbox = os.path.join(indir, "inbox")
    result = {"invoice": [], "other": []}
    if not os.path.isdir(inbox):
        return result
    for fn in sorted(os.listdir(inbox)):
        path = os.path.join(inbox, fn)
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8", errors="replace") as fh:
            first = (fh.read().splitlines() or [""])[0].strip()
        bucket = "invoice" if first == "INVOICE" else "other"
        result[bucket].append(fn)
    for b in result:
        result[b].sort()
    return result


def _parse_ledger(hxdir):
    unified = {}
    if not os.path.isdir(hxdir):
        return unified
    for fname in sorted(os.listdir(hxdir)):
        path = os.path.join(hxdir, fname)
        if not os.path.isfile(path):
            continue
        low = fname.lower()
        try:
            if low.endswith(".csv"):
                import pandas as pd
                df = pd.read_csv(path)
                for _, r in df.iterrows():
                    unified[str(r["invoice_id"])] = (float(r["amount"]), float(r["fee"]))
            elif low.endswith(".json"):
                with open(path) as fh:
                    for obj in json.load(fh):
                        unified[str(obj["invoice_id"])] = (float(obj["amount"]), float(obj["fee"]))
            elif low.endswith(".parquet"):
                import pandas as pd
                df = pd.read_parquet(path)
                for _, r in df.iterrows():
                    unified[str(r["invoice_id"])] = (float(r["amount"]), float(r["fee"]))
        except Exception:
            continue
    return unified


def _read_masks(path):
    rows = []
    if not os.path.exists(path):
        return rows
    with open(path) as fh:
        for r in csv.DictReader(fh):
            rows.append({
                "invoice_id": str(r["invoice_id"]).strip(),
                "r0": int(r["row0"]), "c0": int(r["col0"]),
                "r1": int(r["row1"]), "c1": int(r["col1"]),
                "expected_fee": float(r["expected_fee"]),
            })
    return rows


def expected(indir):
    """Return the full expected result dict for a scenario directory."""
    cfg = _load_config(indir)
    masks = _read_masks(os.path.join(indir, "masks.csv"))
    unified = _parse_ledger(os.path.join(indir, "hx"))
    rows_g, cols_g = int(cfg["grid"]["rows"]), int(cfg["grid"]["cols"])
    it = ITERATIONS

    # mart (N x 3, masks order) + order rows
    mart_rows = []
    order = []
    for m in masks:
        inv = m["invoice_id"]
        amount, fee = unified.get(inv, (0.0, 0.0))
        mart_rows.append([float(amount), float(fee),
                          (float(amount) + float(fee)) * it])
        order.append((inv, float(amount), float(fee),
                      (float(amount) + float(fee)) * it))

    # prompts + per-row mask grids
    prompts = []
    grid_count = 0
    for i, m in enumerate(masks):
        r0, r1 = min(m["r0"], m["r1"]), max(m["r0"], m["r1"])
        c0, c1 = min(m["c0"], m["c1"]), max(m["c0"], m["c1"])
        prompts.append("prompt[%d] invoice=%s rect=(%d,%d,%d,%d)"
                       % (i + 1, m["invoice_id"], r0, c0, r1, c1))
        grid_count += 1

    # mismatch ids
    mis = []
    for m in masks:
        _, fee = unified.get(m["invoice_id"], (0.0, 0.0))
        if abs(float(fee) - m["expected_fee"]) > 1e-9:
            mis.append(m["invoice_id"])

    # sheet lines (exact addresses) — deterministic order A<k>,B<k>,C<k>,TOTAL,NOTE
    sheet = []
    for idx, (inv, amount, fee, prod) in enumerate(order):
        k = idx + 1
        sheet.append({"sheet": "GJ", "address": "A%d" % k, "value": amount, "invoice": inv})
        sheet.append({"sheet": "GJ", "address": "B%d" % k, "value": fee, "invoice": inv})
        sheet.append({"sheet": "GJ", "address": "C%d" % k, "value": prod, "invoice": inv})
    sheet.append({"sheet": "GJ", "address": "TOTAL",
                  "value": float(sum(r[3] for r in order)), "invoice": "*"})
    sheet.append({"sheet": "GJ", "address": "NOTE",
                  "value": (",".join(mis) if mis else "OK"), "invoice": "*"})

    # ranked candidates
    close = cfg.get("close", {})
    target = float(close.get("target", 50.0))
    tol = float(close.get("tolerance", 25.0))
    ranked = []
    path = os.path.join(indir, "candidates.json")
    if os.path.exists(path):
        for c in json.load(open(path)):
            metric = float(c["metric"])
            dist = abs(metric - target)
            if dist <= tol:
                ranked.append({
                    "id": str(c["id"]).strip(),
                    "metric": float(metric),
                    "target": float(target),
                    "distance": round(dist, 4),
                    "score": round(1.0 / (1.0 + dist), 6),
                })
    ranked.sort(key=lambda r: (-r["score"], r["id"]))

    return {
        "mart": np.array(mart_rows, dtype=np.float64).reshape(-1, 3),
        "prompts": prompts,
        "mismatch": ",".join(mis) if mis else "NONE",
        "sheet": sheet,
        "ranked": ranked,
        "grid_count": grid_count,
        "grid_shape": (rows_g, cols_g),
    }
