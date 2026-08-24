#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Legacy Python 2 climate station analyzer.

Reads a monthly climate table (stations x years x {12 monthly temps,
12 monthly precipitations}), computes annual measures per station-year and a
climatology per station, and writes tab-separated outputs.

Runs ONLY under Python 2. Requires: Python 2.7 (no third-party deps).

usage: python legacy_climate.py INPUT OUTPUT_DIR MODE
  MODE = legacy   reproduce the historical output (Python-2 integer division)
  MODE = modern   exact floating-point arithmetic + per-station linear trend
"""
import os
import sys


def read_rows(path):
    rows = []
    with open(path, 'rb') as fh:
        fh.readline()  # header
        for line in fh:
            line = line.decode('ascii').strip()
            if not line:
                continue
            rows.append(line.split('\t'))
    return rows


def main():
    if len(sys.argv) < 4:
        print 'usage: legacy_climate.py INPUT OUTPUT_DIR MODE'
        sys.exit(1)
    input_path, out_dir, mode = sys.argv[1], sys.argv[2], sys.argv[3]
    if not os.path.exists(out_dir):
        os.makedirs(out_dir)

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
    out = ['station\tyear\tTmean\tPtot\tWet']
    for st, yr, tm, pt, wt in annual:
        out.append('%s\t%d\t%.6f\t%.6f\t%d' % (st, yr, tm, pt, wt))
    with open(os.path.join(out_dir, 'annual_means.tsv'), 'w') as fh:
        fh.write('\n'.join(out) + '\n')

    # Per-station climatology. NOTE the historical artefact: in Python 2 the
    # expression `cum / n` with two int operands performs FLOOR division.
    # A naive Python-3 port silently changes this to exact float division.
    clim = []
    for st in sorted(by_station.keys()):
        ys = [t for (_, t) in by_station[st]]
        n = len(ys)
        cum = 0
        for t in ys:
            cum += int(round(t * 100.0))
        if mode == 'legacy':
            scaled = cum / n          # Python 2: int floor division
        else:
            scaled = cum / float(n)   # exact float
        clim.append((st, n, scaled / 100.0))
    with open(os.path.join(out_dir, 'station_clim.tsv'), 'w') as fh:
        fh.write('station\tn\tclimatology\n')
        for st, n, cv in clim:
            fh.write('%s\t%d\t%.6f\n' % (st, n, cv))

    if mode == 'modern':
        with open(os.path.join(out_dir, 'trend.tsv'), 'w') as fh:
            fh.write('station\tslope\n')
            for st in sorted(by_station.keys()):
                xs = [y for (y, _) in by_station[st]]
                ts = [t for (_, t) in by_station[st]]
                mx = sum(xs) / float(len(xs))
                my = sum(ts) / float(len(ts))
                num = sum((x - mx) * (y - my) for x, y in zip(xs, ts))
                den = sum((x - mx) ** 2 for x in xs)
                sl = num / den if abs(den) > 1e-12 else 0.0
                fh.write('%s\t%.6f\n' % (st, sl))


if __name__ == '__main__':
    main()