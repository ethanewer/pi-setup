#!/usr/bin/env python3
"""Expected-report computation + comparison for vanta-mesa verifier.

Usage: python3 verify.py <config.json> <report.json>

Derives the expected JSON report directly from the scenario config (the same
semantics origin.py renders) and compares it to the client's report.
"""
import json
import sys


def expected_from_config(cfg):
    plants = []
    for o in cfg.get("offers", []):
        price = None if o.get("price") is None else float(o["price"])
        st = o.get("stock")
        if st is None:
            stock = None
        elif st == "sold-out":
            stock = 0
        else:
            stock = int(st)
        plants.append({"sku": o["sku"], "cultivar": o["cultivar"],
                       "price": price, "stock": stock})
    return {"title": cfg["title"], "plants": plants}


def norm(rep):
    assert isinstance(rep, dict), rep
    assert set(rep.keys()) == {"title", "plants"}, sorted(rep.keys())
    assert isinstance(rep["title"], str)
    out = []
    for p in rep["plants"]:
        assert set(p.keys()) == {"sku", "cultivar", "price", "stock"}, p
        assert isinstance(p["sku"], str) and isinstance(p["cultivar"], str)
        price = None if p["price"] is None else round(float(p["price"]), 4)
        stock = None if p["stock"] is None else int(p["stock"])
        out.append({"sku": p["sku"], "cultivar": p["cultivar"],
                    "price": price, "stock": stock})
    return {"title": rep["title"].strip(), "plants": out}


def main():
    cfg_path, rep_path = sys.argv[1], sys.argv[2]
    with open(cfg_path, "r", encoding="utf-8") as fh:
        want = expected_from_config(json.load(fh))
    with open(rep_path, "r", encoding="utf-8") as fh:
        got = norm(json.load(fh))
    want = norm(want)
    if got != want:
        print("MISMATCH\nwant=%r\ngot=%r" % (want, got), file=sys.stderr)
        return 1
    print("report ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
