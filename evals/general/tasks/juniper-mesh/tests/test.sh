#!/bin/bash
# Verifier for juniper-mesh: re-executes /app/bnfit.py on the visible fixtures
# and on every hidden case, recomputes the discovery rule / OLS fit from the
# data independently, runs two-sample KS tests on the synthetic marginals
# against the true generating process, and checks determinism. Writes REWARD
# (0/1) to /logs/verifier/reward.txt. Never crashes on malformed agent output.
set -u
mkdir -p /logs/verifier

python3 - <<'PY'
import bisect, json, math, os, random, shutil, subprocess, sys

SOLVER = "/app/bnfit.py"
KS_MAX = 0.04
CORR_TOL = 0.08
failures = []


def read_csv(path):
    with open(path) as f:
        lines = [l.strip() for l in f if l.strip()]
    header = lines[0].split(",")
    data = {c: [] for c in header}
    for l in lines[1:]:
        for c, v in zip(header, l.split(",")):
            data[c].append(float(v))
    return data


def pearson(a, b):
    n = len(a)
    ma = sum(a) / n
    mb = sum(b) / n
    cov = sum((x - ma) * (y - mb) for x, y in zip(a, b))
    va = math.sqrt(sum((x - ma) ** 2 for x in a))
    vb = math.sqrt(sum((y - mb) ** 2 for y in b))
    if va == 0.0 or vb == 0.0:
        return 0.0
    return cov / (va * vb)


def solve(A, b):
    k = len(b)
    M = [row[:] + [b[i]] for i, row in enumerate(A)]
    for col in range(k):
        piv = max(range(col, k), key=lambda r: abs(M[r][col]))
        if abs(M[piv][col]) < 1e-10:
            raise ValueError("singular")
        M[col], M[piv] = M[piv], M[col]
        pv = M[col][col]
        M[col] = [x / pv for x in M[col]]
        for r in range(k):
            if r != col and M[r][col] != 0.0:
                f = M[r][col]
                M[r] = [x - f * y for x, y in zip(M[r], M[col])]
    return [M[i][k] for i in range(k)]


def ols(y, parents, data):
    n = len(y)
    cols = [[1.0] * n] + [data[p] for p in parents]
    k = len(cols)
    A = [[sum(cols[i][t] * cols[j][t] for t in range(n)) for j in range(k)] for i in range(k)]
    b = [sum(cols[i][t] * y[t] for t in range(n)) for i in range(k)]
    beta = solve(A, b)
    resid = [y[t] - sum(cols[i][t] * beta[i] for i in range(k)) for t in range(n)]
    m = sum(resid) / n
    sd = math.sqrt(sum((r - m) ** 2 for r in resid) / n)
    return beta[0], {p: beta[i + 1] for i, p in enumerate(parents)}, sd


def ks(a, b):
    a = sorted(a)
    b = sorted(b)
    n, m = len(a), len(b)
    d = 0.0
    for x in set(a) | set(b):
        i = bisect.bisect_right(a, x)
        j = bisect.bisect_right(b, x)
        d = max(d, abs(i / n - j / m))
    return d


def ref_sample(truth, order, n, seed):
    rng = random.Random(seed)
    rows = {c: [] for c in order}
    for _ in range(n):
        val = {}
        for c in order:
            m = truth["model"][c]
            v = m["intercept"] + sum(co * val[p] for p, co in m["coefficients"].items())
            v += rng.gauss(0.0, m["resid_std"])
            val[c] = v
            rows[c].append(v)
    return rows


def run_solver(data_csv, spec_json, outdir, label):
    if os.path.isdir(outdir):
        shutil.rmtree(outdir)
    os.makedirs(outdir, exist_ok=True)
    if not os.path.isfile(SOLVER):
        failures.append("%s: missing /app/bnfit.py" % label)
        return None
    try:
        r = subprocess.run([sys.executable, SOLVER, data_csv, spec_json, outdir],
                           capture_output=True, text=True, timeout=240)
    except Exception as e:
        failures.append("%s: solver crashed (%s)" % (label, e))
        return None
    if r.returncode != 0:
        failures.append("%s: solver rc=%d stderr=%.200s" % (label, r.returncode, r.stderr))
        return None
    return outdir


def check_case(data_csv, spec_json, truth_path, outdir, label):
    out = run_solver(data_csv, spec_json, outdir, label)
    if out is None:
        return
    spec = json.load(open(spec_json))
    order = spec["order"]
    thr = float(spec["edge_threshold"])
    data = read_csv(data_csv)
    n = len(data[order[0]])

    # --- expected edges from the rule ---
    exp_edges = set()
    for ci, c in enumerate(order):
        for p in order[:ci]:
            if abs(pearson(data[p], data[c])) >= thr:
                exp_edges.add((p, c))

    # --- expected parametric fit (exact OLS under discovered edges) ---
    exp_fit = {}
    for c in order:
        parents = [p for p in order if (p, c) in exp_edges]
        y = data[c]
        if parents:
            b0, coefs, sd = ols(y, parents, data)
        else:
            m = sum(y) / n
            b0, coefs = m, {}
            sd = math.sqrt(sum((v - m) ** 2 for v in y) / n)
        exp_fit[c] = (b0, coefs, sd)

    # --- edges.csv ---
    try:
        with open(os.path.join(out, "edges.csv")) as f:
            lines = [l.strip() for l in f if l.strip()]
        if lines[0] != "parent,child":
            failures.append("%s: edges.csv bad header" % label)
        got_edges = set()
        for l in lines[1:]:
            p, c = l.split(",")
            got_edges.add((p, c))
        if got_edges != exp_edges:
            failures.append("%s: edges mismatch (got %d, expected %d)" %
                            (label, len(got_edges), len(exp_edges)))
    except Exception as e:
        failures.append("%s: edges.csv unreadable (%s)" % (label, e))
        return

    # --- fit.json ---
    try:
        fit = json.load(open(os.path.join(out, "fit.json")))
    except Exception as e:
        failures.append("%s: fit.json unreadable (%s)" % (label, e))
        return
    if not isinstance(fit, dict) or set(fit.keys()) != set(order):
        failures.append("%s: fit.json keys wrong" % label)
        return
    for c in order:
        try:
            b0, coefs, sd = fit[c]["intercept"], fit[c]["coefficients"], fit[c]["resid_std"]
        except Exception:
            failures.append("%s: fit.json[%s] malformed" % (label, c))
            return
        eb0, ecoefs, esd = exp_fit[c]
        if set(coefs.keys()) != set(ecoefs.keys()):
            failures.append("%s: %s coefficient parents wrong" % (label, c))
            return
        if abs(b0 - eb0) > 0.02 + 0.05 * abs(eb0):
            failures.append("%s: %s intercept off (got %.4f want %.4f)" % (label, c, b0, eb0))
        if abs(sd - esd) > 0.02 + 0.05 * esd:
            failures.append("%s: %s resid_std off (got %.4f want %.4f)" % (label, c, sd, esd))
        for p, v in coefs.items():
            if abs(v - ecoefs[p]) > 0.02 + 0.05 * abs(ecoefs[p]):
                failures.append("%s: %s~%s coef off (got %.4f want %.4f)" %
                                (label, c, p, v, ecoefs[p]))

    # --- synthetic.csv ---
    try:
        syn = read_csv(os.path.join(out, "synthetic.csv"))
    except Exception as e:
        failures.append("%s: synthetic.csv unreadable (%s)" % (label, e))
        return
    if list(syn.keys()) != order:
        failures.append("%s: synthetic header wrong" % label)
        return
    if len(syn[order[0]]) != int(spec["samples"]):
        failures.append("%s: synthetic row count wrong" % label)
        return
    truth = json.load(open(truth_path))
    ref = ref_sample(truth, order, int(spec["samples"]), int(truth["ref_seed"]))
    for c in order:
        col = syn[c]
        if any(isinstance(v, complex) or v != v or math.isinf(v) for v in col[:100]):
            failures.append("%s: synthetic %s has non-finite values" % (label, c))
            return
        stat = ks(col, ref[c])
        if stat > KS_MAX:
            failures.append("%s: synthetic %s KS=%.4f > %.2f" % (label, c, stat, KS_MAX))
    # cross-column dependence: each discovered edge's correlation must survive
    for p, c in exp_edges:
        r_syn = pearson(syn[p], syn[c])
        r_dat = pearson(data[p], data[c])
        if abs(r_syn - r_dat) > CORR_TOL:
            failures.append("%s: synthetic corr(%s,%s)=%.3f too far from data %.3f" %
                            (label, p, c, r_syn, r_dat))
    return out


# ---- visible case (also verifies the /app deliverable copies) ----
vis = check_case("/app/sensors.csv", "/app/network.json", "/tests/truth.json",
                 "/tmp/jm_verify_visible", "visible")
if vis is not None:
    for name, got in (("edges.csv", "/app/edges.csv"),
                      ("fit.json", "/app/fit.json"),
                      ("synthetic.csv", "/app/synthetic.csv")):
        want = os.path.join(vis, name)
        if not os.path.isfile(got):
            failures.append("missing %s" % got)
        else:
            a = open(got, "rb").read()
            b = open(want, "rb").read()
            if a != b:
                failures.append("%s differs from a fresh solver run" % got)

# ---- hidden cases ----
hidden = "/tests/hidden"
if os.path.isdir(hidden):
    cases = sorted(os.listdir(hidden))
    if not cases:
        failures.append("no hidden cases present")
    for c in cases:
        base = os.path.join(hidden, c)
        need = [os.path.join(base, n) for n in ("sensors.csv", "network.json", "truth.json")]
        if not all(os.path.isfile(p) for p in need):
            failures.append("hidden '%s' malformed" % c)
            continue
        # determinism: two runs must be byte-identical
        out1 = "/tmp/jm_verify_%s_1" % c
        out2 = "/tmp/jm_verify_%s_2" % c
        check_case(need[0], need[1], need[2], out1, "hidden/%s" % c)
        if os.path.isdir(out1):
            if run_solver(need[0], need[1], out2, "hidden/%s-rerun" % c) is not None:
                for name in ("edges.csv", "fit.json", "synthetic.csv"):
                    a, b = os.path.join(out1, name), os.path.join(out2, name)
                    if os.path.isfile(a) and os.path.isfile(b):
                        if open(a, "rb").read() != open(b, "rb").read():
                            failures.append("hidden/%s: %s not deterministic" % (c, name))
else:
    failures.append("no hidden cases directory")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

rc=$?
if [ $rc -eq 0 ]; then reward=1; else reward=0; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
