#!/bin/bash
set -euo pipefail

cat > /app/migrate.py <<'PY'
#!/usr/bin/env python3
"""Python-3 port of the legacy Python-2 dual-file climate QC analyzer."""
import argparse
import os


def load(path, ncols):
    d = {}
    with open(path, "r", encoding="ascii") as fh:
        fh.readline()
        for line in fh:
            line = line.strip()
            if not line:
                continue
            parts = line.split("\t")
            d[(parts[0], int(parts[1]))] = [float(x) for x in parts[2:2 + ncols]]
    return d


def run(temps_path, precip_path, out_dir, mode):
    os.makedirs(out_dir, exist_ok=True)
    T = load(temps_path, 12)
    P = load(precip_path, 12)
    keys = sorted(set(T) & set(P))

    mlines = ["station\tyear\t" + "\t".join(f"T{i+1}" for i in range(12)) +
              "\t" + "\t".join(f"P{i+1}" for i in range(12))]
    for (s, y) in keys:
        mlines.append("\t".join([s, str(y)] +
                                [f"{v:.2f}" for v in T[(s, y)]] +
                                [f"{v:.2f}" for v in P[(s, y)]]))
    with open(os.path.join(out_dir, "merged.tsv"), "w") as fh:
        fh.write("\n".join(mlines) + "\n")

    annual = []
    by_st = {}
    for (s, y) in keys:
        t, p = T[(s, y)], P[(s, y)]
        tmean = sum(t) / 12.0
        ptot = sum(p)
        wet = sum(1 for v in p if v > 50.0)
        annual.append((s, y, tmean, ptot, wet))
        by_st.setdefault(s, []).append((y, tmean))
    annual.sort(key=lambda r: (r[0], r[1]))
    with open(os.path.join(out_dir, "annual_means.tsv"), "w") as fh:
        fh.write("station\tyear\tTmean\tPtot\tWet\n")
        for s, y, tm, pt, wt in annual:
            fh.write(f"{s}\t{y}\t{tm:.6f}\t{pt:.6f}\t{wt}\n")

    with open(os.path.join(out_dir, "station_clim.tsv"), "w") as fh:
        fh.write("station\tn\tclimatology\n")
        for s in sorted(by_st):
            ys = [t for _, t in by_st[s]]
            n = len(ys)
            cum = sum(int(round(t * 100.0)) for t in ys)
            scaled = cum // n if mode == "legacy" else cum / n
            fh.write(f"{s}\t{n}\t{scaled/100.0:.6f}\n")

    if mode == "modern":
        with open(os.path.join(out_dir, "trend.tsv"), "w") as fh:
            fh.write("station\tslope\n")
            for s in sorted(by_st):
                xs = [y for y, _ in by_st[s]]
                ts = [t for _, t in by_st[s]]
                mx = sum(xs) / len(xs)
                my = sum(ts) / len(ts)
                num = sum((x - mx) * (y - my) for x, y in zip(xs, ts))
                den = sum((x - mx) ** 2 for x in xs)
                sl = num / den if abs(den) > 1e-12 else 0.0
                fh.write(f"{s}\t{sl:.6f}\n")

    stations = sorted(set(k[0] for k in T) | set(k[0] for k in P))
    with open(os.path.join(out_dir, "qc.tsv"), "w") as fh:
        fh.write("station\tn_years\tmin_year\tmax_year\tmissing\n")
        for s in stations:
            sy = sorted(y for (st, y) in T if st == s)
            sp = sorted(y for (st, y) in P if st == s)
            n = len(sy)
            lo = min(sy) if sy else 0
            hi = max(sy) if sy else 0
            missing = len([y for y in range(lo, hi + 1) if y not in sp])
            fh.write(f"{s}\t{n}\t{lo}\t{hi}\t{missing}\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--temps", required=True)
    ap.add_argument("--precip", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--mode", choices=["legacy", "modern"], default="modern")
    args = ap.parse_args()
    run(args.temps, args.precip, args.output, args.mode)


if __name__ == "__main__":
    main()
PY

cat > /app/regress.py <<'PY'
#!/usr/bin/env python3
"""Compare legacy vs modern output directories."""
import argparse
import os
import sys


def read(p):
    with open(p, "r", encoding="ascii") as f:
        return f.read().splitlines()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--legacy-out", required=True)
    ap.add_argument("--modern-out", required=True)
    args = ap.parse_args()
    legacy, modern = args.legacy_out, args.modern_out
    pairs = [("merged.tsv", "IDENTICAL"), ("annual_means.tsv", "IDENTICAL"),
             ("station_clim.tsv", "DIFFER"), ("qc.tsv", "IDENTICAL")]
    ok = True
    for name, expected in pairs:
        lp, mp = os.path.join(legacy, name), os.path.join(modern, name)
        la, ma = read(lp), read(mp)
        verdict = "IDENTICAL" if la == ma else "DIFFER"
        print(f"{name}: {verdict}")
        if verdict != expected:
            ok = False
    lt = os.path.join(legacy, "trend.tsv")
    mt = os.path.join(modern, "trend.tsv")
    legacy_has, modern_has = os.path.exists(lt), os.path.exists(mt)
    print(f"trend.tsv: {'modern-only' if (not legacy_has and modern_has) else 'unexpected'}")
    if not (not legacy_has and modern_has):
        ok = False
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
PY

cd /app
python3 migrate.py --temps climate/temps.tsv --precip climate/precip.tsv --output out_legacy --mode legacy
python3 migrate.py --temps climate/temps.tsv --precip climate/precip.tsv --output out_modern --mode modern
python3 regress.py --legacy-out out_legacy --modern-out out_modern
echo "oracle OK"