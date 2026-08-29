#!/bin/bash
#
# Oracle for quartz-forge. Writes the deliverable generator into /app and runs it
# against the visible config to produce all five artifacts. This does the real work
# (it never reads /tests and never pastes a precomputed answer).
set -euo pipefail

cat > /app/forge_report.py <<'PY'
#!/usr/bin/env python3
"""quartz-forge deliverable generator.

Usage: forge_report.py [CONFIG_PATH]
Reads a config JSON (default /app/data/config.json) and writes these artifacts
into /app:
  report.txt      headline stats + top-10 table (exact fixed-width layout)
  decision.txt    invest/defer flags + maximized NPV
  result.txt      single-line result record
  out.jpg         JPEG rendering of the configured phrase
  construct.txt   designed construct sequence trimmed to the configured ceiling
"""
import json
import sys

from PIL import Image, ImageDraw, ImageFont


def build_report(cfg):
    records = cfg["records"]
    n = len(records)
    unique_sites = len({r["site"] for r in records})
    total_analyzed = sum(r["count"] for r in records)
    top = sorted(records, key=lambda r: (-r["count"], r["site"]))[:10]

    lines = ["QUARTZ FORGE DAILY TELEMETRY", "=" * 28]
    for label, val in [("TOTAL TRACES", n), ("UNIQUE SITES", unique_sites),
                       ("TOTAL ANALYZED", total_analyzed)]:
        lines.append(label.ljust(18) + ": " + "%5d" % val)
    lines.append("")
    lines.append("TOP-10 SITES BY TRACE COUNT")
    lines.append("")
    for i, r in enumerate(top, 1):
        lines.append("  %2d  %-15s count=%4d" % (i, r["site"], r["count"]))
        lines.append("     L:%5d  M:%5d  R:%5d" % (r["frame_l"], r["frame_m"], r["frame_r"]))
    return "\n".join(lines) + "\n"


def build_decision(cfg):
    inv = cfg["investment"]
    npv = -inv["capex"] + sum(cf / (1.0 + inv["rate"]) ** (i + 1)
                              for i, cf in enumerate(inv["cashflows"]))
    npv = round(npv, 2)
    invest = "yes" if npv > 0 else "no"
    defer = "no" if invest == "yes" else "yes"
    return "INVEST=%s\nDEFER=%s\nNPV=%.2f\n" % (invest, defer, npv)


def build_result(cfg):
    return "RESULT=complete records=%d\n" % len(cfg["records"])


def build_construct(cfg):
    seq = "".join(sorted({r["site"] for r in cfg["records"]}))
    return seq[: cfg["max_construct_len"]] + "\n"


def build_jpg(cfg):
    img = Image.new("RGB", (900, 200), (0, 0, 0))
    d = ImageDraw.Draw(img)
    font = ImageFont.load_default()
    d.text((20, 80), cfg["phrase"], fill=(255, 255, 255), font=font)
    img.save("/app/out.jpg", format="JPEG", quality=90)


def main():
    cfg_path = sys.argv[1] if len(sys.argv) > 1 else "/app/data/config.json"
    with open(cfg_path) as fh:
        cfg = json.load(fh)
    with open("/app/report.txt", "w") as fh:
        fh.write(build_report(cfg))
    with open("/app/decision.txt", "w") as fh:
        fh.write(build_decision(cfg))
    with open("/app/result.txt", "w") as fh:
        fh.write(build_result(cfg))
    with open("/app/construct.txt", "w") as fh:
        fh.write(build_construct(cfg))
    build_jpg(cfg)


if __name__ == "__main__":
    main()
PY

chmod +x /app/forge_report.py
python3 /app/forge_report.py

echo "Oracle complete."
