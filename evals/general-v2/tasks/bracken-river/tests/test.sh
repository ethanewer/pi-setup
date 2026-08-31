#!/bin/bash
# Verifier for bracken-river: re-runs the idempotent installer, checks R is
# available on PATH and via settings.json, and EXECUTES the pipeline launcher
# deliverable on the visible case and on every hidden parameter set,
# comparing against an independent R recomputation. Writes reward to
# /logs/verifier/reward.txt. Never crashes on malformed agent output.
set -u
mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import json, os, re, subprocess, sys

failures = []

def run(cmd, **kw):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=120, **kw)
    except Exception as exc:
        failures.append("command %r raised %s" % (cmd[0] if cmd else cmd, exc))
        return None

# --- 1. Idempotency: re-run the installer on the repaired box.
r = run(["bash", "/app/setup_r.sh"])
if r is None or r.returncode != 0:
    failures.append("setup_r.sh re-run failed (exit %s)" % (r.returncode if r else "?"))

# --- 2. Bare-name Rscript on PATH in a fresh shell.
r = run(["Rscript", "--vanilla", "-e", 'cat("R_OK")'])
if r is None or r.returncode != 0 or "R_OK" not in (r.stdout or ""):
    failures.append("bare-name Rscript not usable on PATH")

# --- 3. settings.json: rscript field must be a working executable.
rscript_field = None
try:
    with open("/app/pipeline/settings.json") as fh:
        settings = json.load(fh)
    rscript_field = settings.get("rscript", "")
except Exception as exc:
    failures.append("settings.json unreadable: %s" % exc)
    rscript_field = None
if isinstance(rscript_field, str) and rscript_field:
    if os.path.isfile(rscript_field) and os.access(rscript_field, os.X_OK):
        r = run([rscript_field, "--vanilla", "-e", 'cat("R_OK")'])
        if r is None or r.returncode != 0 or "R_OK" not in (r.stdout or ""):
            failures.append("settings.json rscript field not executable")
    else:
        failures.append("settings.json rscript field not an existing executable file")
else:
    failures.append("settings.json rscript field empty/missing")

# --- Independent recomputation of the sampler spec, using the SAME R the
# agent installed (the grader's reference for the five statistics).
def parse_params(path):
    kv = {}
    with open(path) as fh:
        for line in fh:
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            if "=" not in s:
                continue
            k, _, v = s.partition("=")
            kv[k.strip()] = v.strip()
    return kv

REF = rscript_field if (isinstance(rscript_field, str) and rscript_field
                        and os.path.isfile(rscript_field)) else "Rscript"

R_SNIPPET = (
    'a <- commandArgs(trailingOnly=TRUE);'
    'seed <- as.integer(a[1]); n <- as.integer(a[2]);'
    'mu <- as.numeric(a[3]); sigma <- as.numeric(a[4]);'
    'set.seed(seed); x <- mu + sigma*rnorm(n);'
    'cat(sprintf("mean=%.6f\\nsd=%.6f\\nmedian=%.6f\\nmin=%.6f\\nmax=%.6f\\n",'
    'mean(x), sd(x), median(x), min(x), max(x)))'
)

def expected_for(params_path):
    kv = parse_params(params_path)
    r = run([REF, "--vanilla", "-e", R_SNIPPET, kv["seed"], kv["n"], kv["mu"], kv["sigma"]])
    if r is None or r.returncode != 0:
        return None
    out = {}
    for line in (r.stdout or "").splitlines():
        if "=" in line:
            k, _, v = line.partition("=")
            out[k.strip()] = float(v)
    return out if set(out) == {"mean", "sd", "median", "min", "max"} else None

def parse_output(path):
    out = {}
    with open(path) as fh:
        for line in fh:
            if "=" in line:
                k, _, v = line.partition("=")
                out[k.strip()] = float(v)
    return out

def stats_match(got, want):
    if not isinstance(got, dict) or set(got) != {"mean", "sd", "median", "min", "max"}:
        return False
    for k, wv in want.items():
        gv = got.get(k)
        if not isinstance(gv, (int, float)) or isinstance(gv, bool):
            return False
        if abs(float(gv) - wv) > 1e-6:
            return False
    return True

LAUNCH = ["python3", "/app/pipeline/riverlaunch.py"]

# --- 4. Visible case: execute the launcher deliverable.
visible_out = "/tmp/bracken_visible_out.txt"
if os.path.exists(visible_out):
    os.remove(visible_out)
r = run(LAUNCH + ["/app/pipeline/params_visible.txt", visible_out])
if r is None or r.returncode != 0:
    failures.append("visible pipeline run failed (exit %s)" % (r.returncode if r else "?"))
else:
    if "RIVERLAUNCH_OK" not in (r.stdout or ""):
        failures.append("visible pipeline run missing RIVERLAUNCH_OK sentinel")
    want = expected_for("/app/pipeline/params_visible.txt")
    if want is None:
        failures.append("grader reference R recomputation failed")
    else:
        try:
            if not stats_match(parse_output(visible_out), want):
                failures.append("visible pipeline output mismatch")
        except Exception as exc:
            failures.append("visible output unreadable: %s" % exc)

# --- 5. selftest.txt deliverable must match the visible expected.
if os.path.isfile("/app/pipeline/selftest.txt"):
    want = expected_for("/app/pipeline/params_visible.txt")
    try:
        if want is not None and not stats_match(parse_output("/app/pipeline/selftest.txt"), want):
            failures.append("selftest.txt mismatch")
    except Exception as exc:
        failures.append("selftest.txt unreadable: %s" % exc)
else:
    failures.append("missing /app/pipeline/selftest.txt")

# --- 6. Hidden cases: unseen parameter sets through the launcher deliverable.
hidden_dir = "/tests/hidden"
if os.path.isdir(hidden_dir):
    cases = sorted(os.listdir(hidden_dir))
    if not cases:
        failures.append("no hidden cases present")
    for case in cases:
        params = os.path.join(hidden_dir, case, "params.txt")
        if not os.path.isfile(params):
            failures.append("hidden '%s' malformed" % case)
            continue
        out = "/tmp/bracken_hidden_out.txt"
        if os.path.exists(out):
            os.remove(out)
        r = run(LAUNCH + [params, out])
        if r is None or r.returncode != 0:
            failures.append("hidden case '%s' launcher failed" % case)
            continue
        want = expected_for(params)
        if want is None:
            failures.append("hidden '%s' reference recompute failed" % case)
            continue
        try:
            if not stats_match(parse_output(out), want):
                failures.append("hidden case '%s' output mismatch" % case)
        except Exception as exc:
            failures.append("hidden case '%s' output unreadable: %s" % (case, exc))
else:
    failures.append("no hidden cases directory")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
