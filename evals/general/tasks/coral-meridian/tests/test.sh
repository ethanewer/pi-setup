#!/bin/bash
# Verifier for coral-meridian (executes-deliverable).
# Checks the visible deliverables (/app/tide.py, /app/peak.json) against the
# provided fixtures, then boots FRESH desk servers on hidden station sets under
# /tests/hidden, EXECUTES /app/tide.py against them (default run, fetch on a
# known station, fetch on an unknown station), and validates the outputs against
# expectations recomputed from the hidden fixture data. The desk server must
# still be alive afterwards. Reward = 1 iff all checks pass.
set -u
mkdir -p /logs/verifier

test -f /app/tide.py   || { echo "0" > /logs/verifier/reward.txt; exit 0; }
test -f /app/peak.json || { echo "0" > /logs/verifier/reward.txt; exit 0; }

python3 - <<'PY'
import json, os, shutil, socket, subprocess, sys, time

DESK = "/app/desk"
STATIONS = os.path.join(DESK, "stations")
TIDE = "/app/tide.py"
PEAK = "/app/peak.json"
HIDDEN = "/tests/hidden"

failures = []
def fail(m):
    failures.append(m)
    print("FAIL:", m, flush=True)

def extreme_sample(samples, which):
    best = None
    for t, v in samples:
        if best is None:
            best = (t, v); continue
        if which == "high":
            if v > best[1] or (v == best[1] and t < best[0]):
                best = (t, v)
        else:
            if v < best[1] or (v == best[1] and t < best[0]):
                best = (t, v)
    return best

def load_stations(sdir):
    out = {}
    for fn in sorted(os.listdir(sdir)):
        if not fn.endswith(".json"):
            continue
        with open(os.path.join(sdir, fn)) as fh:
            d = json.load(fh)
        out[str(d["station"])] = [[int(t), int(v)] for t, v in d["samples"]]
    return out

def peak_station(sts):
    """Highest peak value across stations; tie -> lexicographically smallest name."""
    best = None
    for name in sorted(sts):
        t, v = extreme_sample(sts[name], "high")
        if best is None or v > best[0]:
            best = (v, name)
    return best[1]

def expected_extreme(sts, name):
    t, v = extreme_sample(sts[name], "high")
    return {"ok": True, "kind": "extreme", "station": name, "which": "high",
            "when": t, "value": v}

def expected_reads(sts, name):
    s = sts[name]
    t, v = extreme_sample(s, "high")
    return {"ok": True, "kind": "reads", "station": name, "samples": s,
            "count": len(s), "peak": [t, v]}

def norm_extreme(o):
    assert isinstance(o, dict), o
    assert o.get("ok") is True, o
    assert o.get("kind") == "extreme", o
    return (str(o["station"]), str(o["which"]), int(o["when"]), int(o["value"]))

def norm_reads(o):
    assert isinstance(o, dict), o
    assert o.get("ok") is True, o
    assert o.get("kind") == "reads", o
    return (str(o["station"]), int(o["count"]),
            [(int(t), int(v)) for t, v in o["samples"]],
            (int(o["peak"][0]), int(o["peak"][1])))

def run(cmd, timeout=60):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)

def kill_desks():
    subprocess.run(["pkill", "-f", "desk/gauge.py"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.4)

def start_desk():
    subprocess.Popen([sys.executable, os.path.join(DESK, "gauge.py")],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.time() + 10
    while time.time() < deadline:
        try:
            socket.create_connection(("127.0.0.1", 47231), timeout=1).close()
            return True
        except Exception:
            time.sleep(0.2)
    return False

def check_peak_file(sts):
    try:
        with open(PEAK) as fh:
            got = json.loads(fh.read().strip())
    except Exception as e:
        fail("/app/peak.json unreadable or not JSON: %r" % (e,)); return
    want = peak_station(sts)
    if norm_extreme(got) != norm_extreme(expected_extreme(sts, want)):
        fail("peak.json %r != expected EXTREME of %r" % (got, want))

kill_desks()

# ---- visible fixtures: deliverable /app/peak.json must already be correct ----
if not os.path.isdir(STATIONS):
    fail("visible stations dir missing")
else:
    vis = load_stations(STATIONS)
    if not vis:
        fail("no visible station data")
    else:
        check_peak_file(vis)

# ---- hidden cases: fresh data, execute the deliverable, recompute expecteds ----
cases = sorted(d for d in os.listdir(HIDDEN)
               if os.path.isdir(os.path.join(HIDDEN, d))) if os.path.isdir(HIDDEN) else []
if len(cases) < 2:
    fail("expected >= 2 hidden cases, found %d" % len(cases))

for case in cases:
    cdir = os.path.join(HIDDEN, case)
    sdir = os.path.join(cdir, "stations")
    if not os.path.isdir(sdir) or not os.listdir(sdir):
        fail("hidden '%s' has no stations/" % case); continue
    kill_desks()
    shutil.rmtree(STATIONS, ignore_errors=True)
    shutil.copytree(sdir, STATIONS)
    if not start_desk():
        fail("hidden '%s': desk did not come up" % case); continue
    try:
        sts = load_stations(STATIONS)
        # (1) default run overwrites /app/peak.json for the hidden data
        r = run([sys.executable, TIDE], timeout=90)
        if r.returncode != 0:
            fail("hidden '%s': tide.py exited %d: %s"
                 % (case, r.returncode, r.stderr[-300:])); continue
        try:
            with open(PEAK) as fh:
                got = json.loads(fh.read().strip())
            want = peak_station(sts)
            if norm_extreme(got) != norm_extreme(expected_extreme(sts, want)):
                fail("hidden '%s': peak.json %r != EXTREME of %r" % (case, got, want))
        except Exception as e:
            fail("hidden '%s': peak.json check error %r" % (case, e))
        # (2) fetch a known station: raw READS reply on stdout
        st = sorted(sts)[0]
        r = run([sys.executable, TIDE, "fetch", st], timeout=60)
        try:
            got = json.loads(r.stdout.strip().splitlines()[-1])
            if norm_reads(got) != norm_reads(expected_reads(sts, st)):
                fail("hidden '%s': fetch %s reply mismatch" % (case, st))
        except Exception as e:
            fail("hidden '%s': fetch %s unparsable stdout %r (%r)"
                 % (case, st, r.stdout[:200], e))
        # (3) fetch an unknown station: ok:false reply, exit 0, no hang
        r = run([sys.executable, TIDE, "fetch", "no-such-station"], timeout=30)
        if r.returncode != 0:
            fail("hidden '%s': fetch unknown exited %d" % (case, r.returncode))
        else:
            try:
                got = json.loads(r.stdout.strip().splitlines()[-1])
                if got.get("ok") is not False:
                    fail("hidden '%s': fetch unknown did not report ok:false: %r"
                         % (case, got))
            except Exception:
                fail("hidden '%s': fetch unknown unparsable stdout %r"
                     % (case, r.stdout[:200]))
        # (4) desk still alive after the client's interactions
        try:
            socket.create_connection(("127.0.0.1", 47231), timeout=2).close()
        except Exception:
            fail("hidden '%s': desk not alive after client runs" % case)
    except subprocess.TimeoutExpired:
        fail("hidden '%s': deliverable run timed out (blocking misuse)" % case)

kill_desks()

print("verify failures:", failures)
if failures:
    open("/logs/verifier/reward.txt", "w").write("0")
else:
    open("/logs/verifier/reward.txt", "w").write("1")
PY
exit 0
