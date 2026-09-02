#!/bin/bash
mkdir -p /logs/verifier /tmp/fresh

if [ ! -f /app/migrate.py ] || [ ! -f /app/regress.py ]; then
  echo "0.0" > /logs/verifier/reward.txt
  exit 0
fi

python3 - <<'PYEOF'
import os, random, subprocess, sys

try:
    os.makedirs("/tmp/fresh", exist_ok=True)

    # ---- deterministic fresh input pair with a missing precip row ----
    import random
    r = random.Random(313131)
    stations = ["K01", "L77", "M23", "N48"]
    years = list(range(2012, 2020))
    tlines = ["station\tyear\t" + "\t".join(f"T{i+1}" for i in range(12))]
    plines = ["station\tyear\t" + "\t".join(f"P{i+1}" for i in range(12))]
    for s in stations:
        for y in years:
            tlines.append("\t".join([s, str(y)] +
                                    [f"{round(20 + (r.random()*2-1)*9, 2):.2f}" for _ in range(12)]))
            if (s, y) == ("M23", 2014):
                continue
            plines.append("\t".join([s, str(y)] +
                                    [f"{round(r.expovariate(1/30.0), 2):.2f}" for _ in range(12)]))
    tpath, ppath = "/tmp/fresh/temps.tsv", "/tmp/fresh/precip.tsv"
    with open(tpath, "w") as f:
        f.write("\n".join(tlines) + "\n")
    with open(ppath, "w") as f:
        f.write("\n".join(plines) + "\n")

    def run_agent(mode, out):
        return subprocess.run(
            ["python3", "/app/migrate.py", "--temps", tpath, "--precip", ppath,
             "--output", out, "--mode", mode],
            capture_output=True, text=True).returncode

    ok_legacy = run_agent("legacy", "/tmp/ag_legacy") == 0
    ok_modern = run_agent("modern", "/tmp/ag_modern") == 0
    if not (ok_legacy and ok_modern):
        open("/logs/verifier/reward.txt", "w").write("0.0")
        sys.exit(0)

    # harness check
    h = subprocess.run(["python3", "/app/regress.py", "--legacy-out",
                        "/tmp/ag_legacy", "--modern-out", "/tmp/ag_modern"],
                       capture_output=True, text=True)
    harness_ok = h.returncode == 0
    harness_ok = h.returncode == 0
    stdout_text = h.stdout
    harness_ok = harness_ok and "merged.tsv: IDENTICAL" in stdout_text \
        and "annual_means.tsv: IDENTICAL" in stdout_text \
        and "qc.tsv: IDENTICAL" in stdout_text \
        and "station_clim.tsv: DIFFER" in stdout_text
    harness_ok = harness_ok and ("trend.tsv: modern-only" in stdout_text)

    # ---- reference implementation ----
    def load(p, ncols):
        d = {}
        with open(p, "r", encoding="ascii") as f:
            f.readline()
            for line in f:
                line = line.strip()
                if not line:
                    continue
                pr = line.split("\t")
                d[(pr[0], int(pr[1]))] = [float(x) for x in pr[2:2 + ncols]]
        return d
    T, P = load(tpath, 12), load(ppath, 12)
    keys = sorted(set(T) & set(P))
    by_st = {}
    for (s, y) in keys:
        tmean = sum(T[(s, y)]) / 12.0
        by_st.setdefault(s, []).append((y, tmean))
    annual = [(s, y, sum(T[(s, y)]) / 12.0, sum(P[(s, y)]),
               sum(1 for v in P[(s, y)] if v > 50.0)) for (s, y) in keys]
    annual.sort(key=lambda r: (r[0], r[1]))

    ref_annual = ["station\tyear\tTmean\tPtot\tWet"]
    for s, y, tm, pt, wt in annual:
        ref_annual.append(f"{s}\t{y}\t{tm:.6f}\t{pt:.6f}\t{wt}")

    ref_merged = ["station\tyear\t" + "\t".join(f"T{i+1}" for i in range(12)) +
                  "\t" + "\t".join(f"P{i+1}" for i in range(12))]
    for (s, y) in keys:
        ref_merged.append("\t".join([s, str(y)] +
                                    [f"{v:.2f}" for v in T[(s, y)]] +
                                    [f"{v:.2f}" for v in P[(s, y)]]))

    def ref_clim_table(mode):
        out = ["station\tn\tclimatology"]
        for s in sorted(by_st):
            ys = [t for _, t in by_st[s]]
            n = len(ys)
            cum = sum(int(round(t * 100.0)) for t in ys)
            scaled = cum // n if mode == "legacy" else cum / n
            out.append(f"{s}\t{n}\t{scaled/100.0:.6f}")
        return out

    ref_log_clim = ref_clim_table("legacy")
    ref_mod_clim = ref_clim_table("modern")

    ref_trend = ["station\tslope"]
    for s in sorted(by_st):
        xs = [y for y, _ in by_st[s]]
        ts = [t for _, t in by_st[s]]
        mx = sum(xs) / len(xs)
        my = sum(ts) / len(ts)
        num = sum((x - mx) * (y - my) for x, y in zip(xs, ts))
        den = sum((x - mx) ** 2 for x in xs)
        sl = num / den if abs(den) > 1e-12 else 0.0
        ref_trend.append(f"{s}\t{sl:.6f}")

    def ref_qc():
        out = ["station\tn_years\tmin_year\tmax_year\tmissing"]
        for s in sorted(set(k[0] for k in T) | set(k[0] for k in P)):
            sy = sorted(y for (st, y) in T if st == s)
            sp = sorted(y for (st, y) in P if st == s)
            n = len(sy)
            lo = min(sy) if sy else 0
            hi = max(sy) if sy else 0
            missing = len([y for y in range(lo, hi + 1) if y not in sp])
            out.append(f"{s}\t{n}\t{lo}\t{hi}\t{missing}")
        return out

    ref_qc_t = ref_qc()

    def get(p):
        with open(p, "r", encoding="ascii") as f:
            return f.read().splitlines()

    checks = {
        "merged": get("/tmp/ag_legacy/merged.tsv") == ref_merged,
        "annual_legacy": get("/tmp/ag_legacy/annual_means.tsv") == ref_annual,
        "annual_modern": get("/tmp/ag_modern/annual_means.tsv") == ref_annual,
        "clim_legacy": get("/tmp/ag_legacy/station_clim.tsv") == ref_log_clim,
        "clim_modern": get("/tmp/ag_modern/station_clim.tsv") == ref_mod_clim,
        "trend_modern": get("/tmp/ag_modern/trend.tsv") == ref_trend,
        "qc_legacy": get("/tmp/ag_legacy/qc.tsv") == ref_qc_t,
        "qc_modern": get("/tmp/ag_modern/qc.tsv") == ref_qc_t,
        "harness": harness_ok,
    }
    npass = sum(checks.values())
    if npass == len(checks):
        reward = 1.0
    elif npass >= 6:
        reward = 0.5
    else:
        reward = 0.0
    open("/logs/verifier/reward.txt", "w").write(repr(reward))
    print(checks, file=sys.stderr)
except Exception as e:
    open("/logs/verifier/reward.txt", "w").write("0.0")
PYEOF