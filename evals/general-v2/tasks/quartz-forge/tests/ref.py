#!/usr/bin/env python3
"""
tests/ref.py — independent ground-truth generator for the quartz-forge task.

Given a config JSON and an output directory, computes the five artifact outputs
exactly as specified in instruction.md and writes them into the output directory.
Invoked by tests/test.sh (never mounted into the agent's workspace). This is the
verifier's oracle: byte-for-byte ground truth shared by every case.
"""
import argparse
import io
import json
import os

from PIL import Image, ImageDraw, ImageFont

REPORT_FIELDS = [
    ("TOTAL TRACES", "total_traces"),
    ("UNIQUE SITES", "unique_sites"),
    ("TOTAL ANALYZED", "total_analyzed"),
]


def build_report(cfg):
    records = cfg["records"]
    n = len(records)
    total_traces = n
    unique_sites = len({r["site"] for r in records})
    total_analyzed = sum(r["count"] for r in records)
    totals = {"total_traces": total_traces, "unique_sites": unique_sites,
              "total_analyzed": total_analyzed}

    top = sorted(records, key=lambda r: (-r["count"], r["site"]))[:10]

    lines = ["QUARTZ FORGE DAILY TELEMETRY", "=" * 28]
    for label, key in REPORT_FIELDS:
        lines.append(label.ljust(18) + ": " + "%5d" % totals[key])
    lines.append("")
    lines.append("TOP-10 SITES BY TRACE COUNT")
    lines.append("")
    for i, r in enumerate(top, 1):
        lines.append("  %2d  %-15s count=%4d" % (i, r["site"], r["count"]))
        lines.append("     L:%5d  M:%5d  R:%5d" % (r["frame_l"], r["frame_m"], r["frame_r"]))
    return "\n".join(lines) + "\n"


def build_decision(cfg):
    inv = cfg["investment"]
    capex = inv["capex"]
    rate = inv["rate"]
    npv = -capex + sum(cf / (1.0 + rate) ** (i + 1) for i, cf in enumerate(inv["cashflows"]))
    npv = round(npv, 2)
    invest = "yes" if npv > 0 else "no"
    defer = "no" if invest == "yes" else "yes"
    return "INVEST=%s\nDEFER=%s\nNPV=%.2f\n" % (invest, defer, npv)


def build_result(cfg):
    n = len(cfg["records"])
    return "RESULT=complete records=%d\n" % n


def build_construct(cfg):
    seq = "".join(sorted({r["site"] for r in cfg["records"]}))
    return seq[: cfg["max_construct_len"]] + "\n"


def build_jpg(cfg):
    img = Image.new("RGB", (900, 200), (0, 0, 0))
    d = ImageDraw.Draw(img)
    font = ImageFont.load_default()
    d.text((20, 80), cfg["phrase"], fill=(255, 255, 255), font=font)
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=90)
    return buf.getvalue()


def compute(cfg):
    return {
        "report.txt": build_report(cfg),
        "decision.txt": build_decision(cfg),
        "result.txt": build_result(cfg),
        "construct.txt": build_construct(cfg),
        "out.jpg": build_jpg(cfg),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cfg")
    ap.add_argument("outdir")
    args = ap.parse_args()
    with open(args.cfg) as fh:
        cfg = json.load(fh)
    os.makedirs(args.outdir, exist_ok=True)
    for name, data in compute(cfg).items():
        mode = "wb" if isinstance(data, bytes) else "w"
        with open(os.path.join(args.outdir, name), mode) as fh:
            fh.write(data)


if __name__ == "__main__":
    main()
