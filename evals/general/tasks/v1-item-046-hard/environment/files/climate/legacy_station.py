#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Legacy Python 2 dual-file climate station QC analyzer.

Reads TWO monthly climate tables (temp + precip), joins them on (station,
year), computes annual measures, per-station climatology, a linear trend
(modern mode), and a data-integrity QC report.

Runs ONLY under Python 2.7 (stdlib only).

usage: python legacy_climate.py --temps T.tsv --precip P.tsv \
       --output OUT_DIR [--mode legacy|modern]
"""
import os
import sys


def parse_arg(argv, flag):
    for i in xrange(len(argv) - 1):
        if argv[i] == flag:
            return argv[i + 1]
    return None


def load(path, ncols):
    data = {}
    with open(path, 'rb') as fh:
        fh.readline()  # header
        for line in fh:
            line = line.decode('ascii').strip()
            if not line:
                continue
            parts = line.split('\t')
            data[(parts[0], int(parts[1]))] = [float(x) for x in parts[2:2 + ncols]]
    return data


def main():
    argv = sys.argv[1:]
    temps_path = parse_table(argv, '--temp')
    precip_path = parse_table(argv, '--precip')
    out_dir = parse_table(argv, '--output')
    mode = parse_table(argv, '--mode')
    if mode is None:
        mode = 'modern'
    if not (temps_path and precip_path and out_dir):
        print 'usage: legacy_station.py --temp T.tsv --precip P.tsv --output OUT [--mode legacy|modern]'
        sys.exit(1)
    if not os.path.exists(out_dir):
        os.makedirs(out_dir)

    T = load(temps_path, 12)
    P = load(precip_path, 12)
    keys = sorted(set(T.keys()) & set(P.keys()))

    # merged table (matched rows only)
    mlines = ['station\tyear\t' + '\t'.join('T%d' % (i + 1) for i in xrange(12)) +
              '\t' + '\t'.join('P%d' % (i + 1) for i in xrange(12))]
    for (s, y) in keys:
        mlines.append('\t'.join([s, str(y)] +
                                ['%.2f' % v for v in T[(s, y)]] +
                                ['%.2f' % v for v in P[(s, y)]]))
    with open(os.path.join(out_dir, 'merged.tsv'), 'w') as fh:
        fh.write('\n'.join(mlines) + '\n')

    # annual measures
    annual = []
    by_station = {}
    for (s, y) in keys:
        t = T[(s, y)]
        p = P[(s, y)]
        tmean = sum(t) / 12.0
        ptot = sum(p)
        wet = sum(1 for v in p if v > 50.0)
        annual.append((s, y, tmean, ptot, wet))
        by_station.setdefault(s, []).append((y, tmean))
    annual.sort(key=lambda r: (r[0], r[1]))
    with open(os.path.join(out_dir, 'annual_means.tsv'), 'w') as fh:
        fh.write('station\tyear\tTmean\tPtot\tWet\n')
        for s, y, tm, pt, wt in annual:
            fh.write('%s\t%d\t%.6f\t%.6f\t%d\n' % (s, y, tm, pt, wt))

    # per-station climatology (Python-2 floor-division artefact)
    with open(os.path.join(out_dir, 'station_clim.tsv'), 'w') as fh:
        fh.write('station\tn\tclimatology\n')
        for s in sorted(by_station.keys()):
            ys = [t for (_, t) in by_station[s]]
            n = len(ys)
            cum = 0
            for t in ys:
                cum += int(round(t * 100.0))
            if mode == 'legacy':
                scaled = cum / n       # Python 2 floors int/int
            else:
                scaled = cum / float(n)
            fh.write('%s\t%d\t%.6f\n' % (s, n, scaled / 100.0))

    if mode == 'modern':
        with open(os.path.join(out_dir, 'trend.tsv'), 'w') as fh:
            fh.write('station\tslope\n')
            for s in sorted(by_station.keys()):
                xs = [y for (y, _) in by_station[s]]
                ts = [t for (_, t) in by_station[s]]
                mx = sum(xs) / float(len(xs))
                my = sum(ts) / float(len(ts))
                num = sum((x - mx) * (y - my) for x, y in zip(xs, ts))
                den = sum((x - mx) ** 2 for x in xs)
                sl = num / den if abs(den) > 1e-12 else 0.0
                fh.write('%s\t%.6f\n' % (s, sl))

    # QC / data-integrity report
    stations = sorted(set([k[0] for k in T.keys()] + [k[0] for k in P.keys()]))
    with open(os.path.join(out_dir, 'qc.tsv'), 'w') as fh:
        fh.write('station\tn_years\tmin_year\tmax_year\tmissing\n')
        for s in stations:
            sy = sorted(y for (st, y) in T.keys() if st == s)
            sp = sorted(y for (st, y) in P.keys() if st == s)
            n = len(sy)
            lo = min(sy) if sy else 0
            hi = max(sy) if sy else 0
            missing = len([y for y in range(lo, hi + 1) if y not in sp])
            fh.write('%s\t%d\t%d\t%d\t%d\n' % (s, n, lo, hi, missing))


if __name__ == '__main__':
    main()