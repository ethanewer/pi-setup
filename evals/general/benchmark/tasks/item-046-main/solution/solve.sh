#!/bin/bash
set -euo pipefail

# Oracle: a faithful Python-3 port of the legacy Python-2 climate analyzer.
cat > /app/migrate.py <<'PY'
#!/usr/bin/env python3
"""Python-3 port of the legacy Python-2 climate station analyzer.

CLI: migrate.py --input IN.tsv --output OUT_DIR [--mode legacy|modern]
"""
import argparse
import os


def read_rows(path):
    rows = []
    with open(path, "r", encoding="ascii") as fh:
        fh.readline()  # header
        for line in fh:
            line = line.strip()
            if line:
                rows.append(line.split("\t"))
    return rows


def run(input_path, out_dir, mode):
    os.makedirs(out_dir, exist_ok=True)
    rows = read_rows(input_path)
    annual = []
    by_station = {}
    for p in rows:
        st = p[0]
        yr = int(p[1])
        temps = [float(x) for x in p[2:14]]
        prec = [float(x) for x in p[14:26]]
        tmean = sum(temps) / 12.0
        ptot = sum(prec)
        wet = sum(1 for v in prec if v > 50.0)
        annual.append((st, yr, tmean, ptot, wet))
        by_station.setdefault(st, []).append((yr, tmean))

    annual.sort(key=lambda r: (r[0], r[1]))
    lines = ["station\tyear\tTmean\tPtot\tWet"]
    for st, yr, tm, pt, wt in annual:
        lines.append(f"{st}\t{yr}\t{tm:.6f}\t{pt:.6f}\t{wt}")
    with open(os.path.join(out_dir, "annual_means.tsv"), "w") as fh:
        fh.write("\n".join(lines) + "\n")

    clim = []
    for st in sorted(by_station):
        ys = [t for _, t in by_station[st]]
        n = len(ys)
        cum = sum(int(round(t * 100.0)) for t in ys)
        # legacy: floor division (Python-2 int/int); modern: exact float
        scaled = cum // n if mode == "legacy" else cum / n
        clim.append((st, n, scaled / 100.0))
    with open(os.path.join(out_dir, "station_clim.tsv"), "w") as fh:
        fh.write("station\tn\tclimatology\n")
        for st, n, cv in clim:
            fh.write(f"{st}\t{n}\t{cv:.6f}\n")

    if mode == "modern":
        with open(os.path.join(out_dir, "trend.tsv"), "w") as fh:
            fh.write("station\tslope\n")
            for st in sorted(by_station):
                xs = [y for y, _ in by_station[st]]
                ts = [t for _, t in by_station[st]]
                mx = sum(xs) / len(xs)
                my = sum(ts) / len(ts)
                num = sum((x - mx) * (y - my) for x, y in zip(xs, ts))
                den = sum((x - mx) ** 2 for x in xs)
                sl = num / den if abs(den) > 1e-12 else 0.0
                fh.write(f"{st}\t{sl:.6f}\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--mode", choices=["legacy", "modern"], default="modern")
    args = ap.parse_args()
    run(args.input, args.output, args.mode)


if __name__ == "__main__":
    main()
PY

# Run both modes on the bundled sample and write the differential report.
cd /app
python3 migrate.py --input climate/temps.tsv --output out_legacy --mode legacy
python3 migrate.py --input climate/temps.tsv --output out_modern --mode modern

if diff -q out_legacy/annual_means.tsv out_modern/annual_means.tsv > /dev/null; then
  annual_same="identical"
else
  annual_same="DIFFER"
fi

cat > /app/differential.md <<'MD'
# item-046 migration report (differential)

(a) Syntax-only fixes:
  - `print` statements -> `print(...)` function calls.
  - binary-mode open + `.decode('ascii')` -> text-mode open with encoding.
  - `%` string formatting kept (still valid in Python 3).
  - no `xrange`/`iteritems` were used; iteration over lists is unchanged.

(b) Behaviour-handling decisions:
  - `cum / n` under Python 2 floors when both operands are int; under Python 3
    it is exact. `--mode legacy` therefore uses explicit `//` to preserve the
    historical floored climatology, while `--mode modern` uses `/` to give the
    exact climatology. This is a behavioural difference, not a syntax one, and
    is handled by an explicit mode switch.
  - `trend.tsv` is only emitted in `modern` mode (matches legacy CLI contract).
MD

echo "annual_means identical across modes: $annual_same"
echo "oracle outputs written to /app/out_legacy and /app/out_modern"