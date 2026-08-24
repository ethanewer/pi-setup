#!/bin/bash
mkdir -p /logs/verifier /tmp/fresh

if [ ! -f /app/migrate.py ] || [ ! -f /app/differential.md ]; then
  echo "0.0" > /logs/verifier/reward.txt
  exit 0
fi

python3 - <<'PYEOF'
import os, random, subprocess, sys

try:
    os.makedirs("/tmp/fresh", exist_ok=True)
    os.makedirs("/tmp/ag_legacy", exist_ok=True)
    os.makedirs("/tmp/ag_modern", exist_ok=True)

    # ---- deterministic fresh input (stdlib only) ----
    r = random.Random(9999923)
    stations = ["Q01", "R22", "S93", "T48", "U42"]
    years = list(range(2007, 2015))
    header = "\t".join(["station", "year"] +
                       [f"T{i+1}" for i in range(12)] +
                       [f"P{i+1}" for i in range(12)])
    rows = [header]
    for s in stations:
        for y in years:
            temps = [f"{round(18 + (r.random()*2-1)*10, 2):.2f}" for _ in range(12)]
            prec = [f"{round(r.expovariate(1/26.0), 2):.2f}" for _ in range(12)]
            rows.append("\t".join([s, str(y)] + temps + prec))
    inp = "/tmp/fresh/temps.tsv"
    with open(inp, "w") as f:
        f.write("\n".join(rows) + "\n")

    def run_agent(mode, out):
        return subprocess.run(
            ["python3", "/app/migrate.py", "--input", inp, "--output", out,
             "--mode", mode],
            capture_output=True, text=True).returncode

    ok_legacy = run_agent("legacy", "/tmp/ag_legacy") == 0
    ok_modern = run_agent("modern", "/tmp/ag_modern") == 0
    if not (ok_legacy and ok_modern):
        open("/logs/verifier/reward.txt", "w").write("0.0")
        sys.exit(0)

    # ---- reference implementation of the same contract ----
    rows = []
    with open(inp, "r", encoding="ascii") as f:
        f.readline()
        for line in f:
            line = line.strip()
            if line:
                rows.append(line.split("\t"))
    annual = []
    by_st = {}
    for p in rows:
        st, yr = p[0], int(p[1])
        temps = [float(x) for x in p[2:14]]
        prec = [float(x) for x in p[14:26]]
        tmean = sum(temps) / 12.0
        ptot = sum(prec)
        wet = sum(1 for v in prec if v > 50.0)
        annual.append((st, yr, tmean, ptot, wet))
        by_st.setdefault(st, []).append((yr, tmean))
    annual.sort(key=lambda r: (r[0], r[1]))

    ref_annual_lines = ["station\tyear\tTmean\tPtot\tWet"]
    for st, yr, tm, pt, wt in annual:
        ref_annual_lines.append(f"{st}\t{yr}\t{tm:.6f}\t{pt:.6f}\t{wt}")
    ref_annual = "\n".join(ref_annual_lines) + "\n"

    def ref_clim(mode):
        out = ["station\tn\tclimatology"]
        for st in sorted(by_st):
            ys = [t for _, t in by_st[st]]
            n = len(ys)
            cum = sum(int(round(t * 100.0)) for t in ys)
            scaled = cum // n if mode == "legacy" else cum / n
            out.append(f"{st}\t{n}\t{scaled / 100.0:.6f}")
        return "\n".join(out) + "\n"

    ref_leg_clim = ref_clim("legacy")
    ref_mod_clim = ref_clim("modern")

    ref_trend_lines = ["station\tslope"]
    for st in sorted(by_st):
        xs = [y for y, _ in by_st[st]]
        ts = [t for _, t in by_st[st]]
        mx = sum(xs) / len(xs)
        my = sum(ts) / len(ts)
        num = sum((x - mx) * (y - my) for x, y in zip(xs, ts))
        den = sum((x - mx) ** 2 for x in xs)
        sl = num / den if abs(den) > 1e-12 else 0.0
        ref_trend_lines.append(f"{st}\t{sl:.6f}")
    ref_trend = "\n".join(ref_trend_lines) + "\n"

    def read(p):
        with open(p, "r", encoding="ascii") as f:
            return "\n".join(f.read().splitlines()) + "\n"

    checks = {
        "annual_legacy": read("/tmp/ag_legacy/annual_means.tsv") == ref_annual,
        "annual_modern": read("/tmp/ag_modern/annual_means.tsv") == ref_annual,
        "clim_legacy": read("/tmp/ag_legacy/station_clim.tsv") == ref_leg_clim,
        "clim_modern": read("/tmp/ag_modern/station_clim.tsv") == ref_mod_clim,
        "trend_modern": read("/tmp/ag_modern/trend.tsv") == ref_trend,
    }
    npass = sum(checks.values())
    reward = 1.0 if npass == 5 else (0.5 if npass >= 3 else 0.0)
    open("/logs/verifier/reward.txt", "w").write(repr(reward))
    print(checks, file=sys.stderr)
except Exception:
    open("/logs/verifier/reward.txt", "w").write("0.0")
PY