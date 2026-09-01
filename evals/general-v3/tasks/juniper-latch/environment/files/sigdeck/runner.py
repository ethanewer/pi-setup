"""Command-line runner: `python3 -m sigdeck.runner <input_csv> <output_json>`.

Reads a two-column CSV (header `t,raw`; `t` is an integer sample tag, `raw`
a hex token decoded by sigdeck.codec), runs the windowing stage over the
decoded samples in file order, and writes a JSON report with keys:
  window -- the frozen window length (sigdeck.constants.WINDOW)
  count  -- number of samples
  rms    -- trailing-window RMS values (4-decimal floats)
  rung   -- quantized ladder rungs
"""

import csv
import json
import sys

from .codec import decode
from .constants import LADDER, WINDOW
from .windowing import moving_rms, quantize


def load_rows(path):
    rows = []
    with open(path, newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        if reader.fieldnames != ["t", "raw"]:
            raise ValueError("expected header 't,raw', got %r" % (reader.fieldnames,))
        for rec in reader:
            rows.append((int(rec["t"]), rec["raw"]))
    return rows


def build_report(rows):
    values = [decode(raw) for _, raw in rows]
    rms = moving_rms(values, WINDOW)
    return {
        "window": WINDOW,
        "count": len(values),
        "rms": rms,
        "rung": [quantize(x) for x in rms],
    }


def main(argv):
    if len(argv) != 3:
        print("usage: python3 -m sigdeck.runner <input_csv> <output_json>",
              file=sys.stderr)
        return 2
    rows = load_rows(argv[1])
    report = build_report(rows)
    import os
    out_dir = os.path.dirname(os.path.abspath(argv[2]))
    os.makedirs(out_dir, exist_ok=True)
    with open(argv[2], "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)
        fh.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
