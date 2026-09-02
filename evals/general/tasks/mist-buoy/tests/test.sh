#!/bin/bash
# Verifier for mist-buoy: EXECUTES the deliverable client (/app/client.py)
# against the visible instance and against fresh hidden instances with
# different data, and checks the /app/report.json deliverable. Writes 0/1 to
# /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import json, os, subprocess, sys, time, urllib.request

CLIENT = "/app/client.py"
VISIBLE_PORT = 8098
HIDDEN_PORTS = [8811, 8812, 8813]


def norm(obj):
    assert isinstance(obj, dict), obj
    assert set(obj.keys()) == {"contract_version", "stations_total",
                               "stations_selected", "report"}, obj.keys()
    rep = obj["report"]
    assert isinstance(rep, dict), rep
    assert set(rep.keys()) == {"stations", "readings", "min", "mean",
                               "max"}, rep.keys()
    stats = {}
    for k in ("min", "mean", "max"):
        v = rep[k]
        stats[k] = None if v is None else round(float(v), 4)
    return {
        "contract_version": str(obj["contract_version"]),
        "stations_total": int(obj["stations_total"]),
        "stations_selected": int(obj["stations_selected"]),
        "report": {"stations": int(rep["stations"]),
                   "readings": int(rep["readings"]), **stats},
    }


def load(path):
    with open(path) as f:
        return json.load(f)


def eq(got_path, want_path):
    try:
        return norm(load(got_path)) == norm(load(want_path))
    except Exception as e:
        print("compare error:", e)
        return False


def run_client(base, out_path):
    if os.path.exists(out_path):
        os.remove(out_path)
    try:
        r = subprocess.run(
            [sys.executable, CLIENT, base, out_path],
            capture_output=True, text=True, timeout=120,
        )
    except Exception as e:
        print("client run error:", e)
        return False
    return r.returncode == 0 and os.path.exists(out_path)


def start_server(data, port):
    proc = subprocess.Popen(
        [sys.executable, "/app/server.py", data, str(port)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(60):
        try:
            with urllib.request.urlopen(
                    "http://127.0.0.1:%d/contract.json" % port, timeout=2) as r:
                if r.status == 200:
                    return proc
        except Exception:
            time.sleep(0.2)
    proc.terminate()
    return None


failures = []

if not os.path.isfile(CLIENT):
    failures.append("missing /app/client.py")
else:
    # --- visible instance (start if the container's own one is down) ---
    proc_vis = start_server("/app/data/visible.json", VISIBLE_PORT)
    if proc_vis is None:
        failures.append("visible instance unreachable")
    else:
        try:
            if not run_client("http://127.0.0.1:%d" % VISIBLE_PORT,
                              "/tmp/mist_vis_out.json"):
                failures.append("visible case: client run failed")
            elif not eq("/tmp/mist_vis_out.json", "/tests/expected.json"):
                failures.append("visible case: output mismatch")
            # /app/report.json deliverable must match the visible expected
            if not os.path.isfile("/app/report.json"):
                failures.append("missing /app/report.json")
            elif not eq("/app/report.json", "/tests/expected.json"):
                failures.append("/app/report.json does not match visible expected")
        finally:
            # terminate the process we spawned; if the instance was already
            # running before start_server, that spawn already exited and this
            # is a harmless no-op that never kills the pre-existing server
            if proc_vis is not None:
                proc_vis.terminate()
                proc_vis.wait()

    # --- hidden instances: distinct data files, fresh processes ---------
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for i, c in enumerate(cases):
            data = os.path.join(hidden_dir, c, "data.json")
            exp = os.path.join(hidden_dir, c, "expected.json")
            if not (os.path.isfile(data) and os.path.isfile(exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            port = HIDDEN_PORTS[i % len(HIDDEN_PORTS)]
            proc = start_server(data, port)
            if proc is None:
                failures.append("hidden '%s': instance failed to start" % c)
                continue
            try:
                out = "/tmp/mist_hidden_out_%s.json" % c
                if not run_client("http://127.0.0.1:%d" % port, out):
                    failures.append("hidden '%s': client run failed" % c)
                elif not eq(out, exp):
                    failures.append("hidden '%s': output mismatch" % c)
            finally:
                proc.terminate()
                proc.wait()

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
