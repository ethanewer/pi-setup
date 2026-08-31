#!/usr/bin/env bash
# dust-tape verifier: re-runs the agent's /app/triage.py on the visible archive
# and on two hidden artifact sets, and cross-checks /app/inventory.json.
# Writes 1/0 to /logs/verifier/reward.txt. Never crashes on malformed output.
set -u
mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import json, os, subprocess, sys

TRIAGE = "/app/triage.py"
CANON = ["format", "arch", "host_executable", "magic_hex", "variant",
         "tsize", "dsize", "bsize", "symsize", "entry", "trsize", "drsize",
         "mem_image"]
failures = []


def run_triage(path):
    """Run the deliverable; return parsed JSON dict or None (never raise)."""
    try:
        r = subprocess.run([sys.executable, TRIAGE, path],
                           capture_output=True, text=True, timeout=60)
    except Exception as exc:
        failures.append("triage crashed on %s: %r" % (path, exc))
        return None
    if r.returncode != 0:
        failures.append("triage exit %d on %s" % (r.returncode, path))
        return None
    try:
        obj = json.loads(r.stdout.strip())
    except Exception:
        failures.append("triage stdout not JSON for %s" % path)
        return None
    if not isinstance(obj, dict) or set(obj) != set(CANON) | {"note"}:
        failures.append("bad keys for %s" % path)
        return None
    return obj


def canon(obj):
    return {k: obj[k] for k in CANON}


# --- 0. deliverables exist ---
if not os.path.isfile(TRIAGE):
    failures.append("missing /app/triage.py")
if not os.path.isfile("/app/inventory.json"):
    failures.append("missing /app/inventory.json")

# --- 1. hidden case A ---
exp_a = "/tests/hidden/set-a/expected.json"
adir = "/tests/hidden/set-a/artifacts"
if os.path.isfile(exp_a) and os.path.isdir(adir):
    try:
        want = json.load(open(exp_a))
        for fn in sorted(want):
            got = run_triage(os.path.join(adir, fn))
            if got is not None and canon(got) != want[fn]:
                failures.append("hidden set-a %s: got %s want %s"
                                % (fn, canon(got), want[fn]))
    except Exception as exc:
        failures.append("set-a harness error: %r" % exc)
else:
    failures.append("hidden set-a inputs missing")

# --- 2. hidden case B ---
exp_b = "/tests/hidden/set-b/expected.json"
bdir = "/tests/hidden/set-b/artifacts"
if os.path.isfile(exp_b) and os.path.isdir(bdir):
    try:
        want = json.load(open(exp_b))
        for fn in sorted(want):
            got = run_triage(os.path.join(bdir, fn))
            if got is not None and canon(got) != want[fn]:
                failures.append("hidden set-b %s: got %s want %s"
                                % (fn, canon(got), want[fn]))
    except Exception as exc:
        failures.append("set-b harness error: %r" % exc)
else:
    failures.append("hidden set-b inputs missing")

# --- 3. visible inventory cross-check ---
if os.path.isfile(TRIAGE) and os.path.isdir("/app/artifacts"):
    try:
        inv = json.load(open("/app/inventory.json"))
        if not (isinstance(inv, dict) and
                set(inv) == {"archive", "pdp11_files",
                             "host_executable_files"}):
            failures.append("inventory.json wrong shape")
        else:
            names = sorted(
                os.path.relpath(os.path.join(dp, fn), "/app/artifacts")
                for dp, _, fns in os.walk("/app/artifacts") for fn in fns)
            if sorted(inv["archive"].keys()) != names:
                failures.append("inventory archive keys wrong")
            else:
                pdp, host = [], []
                for fn in names:
                    got = run_triage(os.path.join("/app/artifacts", fn))
                    if got is None:
                        continue
                    if canon(got) != canon(inv["archive"][fn]):
                        failures.append(
                            "inventory %s disagrees with triage.py" % fn)
                    if got["arch"] == "pdp11":
                        pdp.append(fn)
                    if got["host_executable"] is True:
                        host.append(fn)
                if sorted(inv["pdp11_files"]) != sorted(pdp):
                    failures.append("pdp11_files wrong")
                if sorted(inv["host_executable_files"]) != sorted(host):
                    failures.append("host_executable_files wrong")
                if "monitor.pdp11" not in inv["pdp11_files"]:
                    failures.append("monitor.pdp11 not classified as pdp11")
    except Exception as exc:
        failures.append("inventory check error: %r" % exc)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
