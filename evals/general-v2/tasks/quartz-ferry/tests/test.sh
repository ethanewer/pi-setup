#!/bin/bash
# Verifier for quartz-ferry: checks the visible report artifact, then EXECUTES
# the deliverable client (/app/client.py) against a fresh reference origin and
# against every hidden deployment in /tests/hidden, validating the report and
# the origin's audit log for one clean login -> tasks -> logout session.
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied origin server (the instruction forbids
# modifying it; tampering would defeat the session audit).
PRISTINE_RELAYD_SHA="$(sha256sum /app/relayd.py 2>/dev/null | awk '{print $1}')"

python3 - "$PRISTINE_RELAYD_SHA" <<'PY'
import json, os, socket, subprocess, sys, time, urllib.request

CLIENT = "/app/client.py"
RELAYD = "/app/relayd.py"
pristine_sha = sys.argv[1]

failures = []

if not os.path.isfile(RELAYD):
    failures.append("missing /app/relayd.py (origin tampered)")
else:
    import hashlib
    actual = hashlib.sha256(open(RELAYD, "rb").read()).hexdigest()
    if actual != pristine_sha or not pristine_sha:
        failures.append("/app/relayd.py was modified")

if not os.path.isfile(CLIENT):
    failures.append("missing /app/client.py")


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def start_origin(scenario, audit):
    port = free_port()
    proc = subprocess.Popen(
        [sys.executable, RELAYD, "--config", scenario,
         "--port", str(port), "--audit", audit],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    url = "http://127.0.0.1:%d/api/challenge" % port
    for _ in range(60):
        if proc.poll() is not None:
            break
        try:
            urllib.request.urlopen(url, timeout=0.5).read()
            return proc, port
        except Exception:
            time.sleep(0.1)
    proc.kill()
    return None, port


def load_audit(path):
    events = []
    if os.path.isfile(path):
        with open(path) as fh:
            for line in fh:
                line = line.strip()
                if line:
                    try:
                        events.append(json.loads(line))
                    except Exception:
                        pass
    return events


def check_audit(events, exp_user, exp_count):
    login_ok = [e for e in events if e.get("event") == "login_ok"]
    if len(login_ok) != 1:
        return "expected exactly 1 login_ok, got %d" % len(login_ok)
    if any(e.get("event") == "login_failed" for e in events):
        return "origin recorded failed authentication attempts"
    if any(e.get("event") == "auth_rejected" for e in events):
        return "origin recorded unauthorized requests"
    tasks_ok = [e for e in events if e.get("event") == "tasks_ok"]
    if not tasks_ok:
        return "no authenticated task fetch recorded"
    if any(int(e.get("count", -1)) != exp_count for e in tasks_ok):
        return "task fetch count mismatch"
    logout_ok = [e for e in events if e.get("event") == "logout_ok"]
    if len(logout_ok) != 1:
        return "expected exactly 1 logout_ok, got %d" % len(logout_ok)
    if events and events[-1].get("event") != "logout_ok":
        return "session not terminated as the final origin event"
    if login_ok[0].get("user") != exp_user:
        return "login_ok user mismatch"
    return None


def check_report(report, scenario, audit):
    try:
        with open(report) as fh:
            got = json.load(fh)
        with open(scenario) as fh:
            cfg = json.load(fh)
    except Exception as exc:
        return "report/config unreadable: %s" % exc
    if not isinstance(got, dict):
        return "report is not a JSON object"
    if set(got.keys()) != {"user", "challenge_used", "session_token",
                           "tasks_count", "logged_out"}:
        return "report keys wrong: %s" % sorted(got.keys())
    if got["user"] != cfg["user"]:
        return "report user mismatch"
    if int(got["tasks_count"]) != len(cfg.get("tasks", [])):
        return "report tasks_count mismatch"
    if got["logged_out"] is not True:
        return "report logged_out not true"
    if not isinstance(got["session_token"], str) or not got["session_token"]:
        return "report session_token missing"
    events = load_audit(audit)
    err = check_audit(events, cfg["user"], len(cfg.get("tasks", [])))
    if err:
        return err
    login_ok = [e for e in events if e.get("event") == "login_ok"][0]
    if got["session_token"] != login_ok.get("session"):
        return "report session_token does not match the origin session"
    if got["challenge_used"] != login_ok.get("challenge"):
        return "report challenge_used does not match the login challenge"
    return None


def run_case(scenario, passfile, user, report_out, tag):
    audit = "/tmp/quartz_ferry_audit_%s.jsonl" % tag
    if os.path.exists(audit):
        os.remove(audit)
    if os.path.exists(report_out):
        os.remove(report_out)
    proc, port = start_origin(scenario, audit)
    if proc is None:
        return "origin failed to start"
    try:
        r = subprocess.run(
            [sys.executable, CLIENT, "--origin",
             "http://127.0.0.1:%d" % port, "--user", user,
             "--passfile", passfile, "--out", report_out],
            capture_output=True, text=True, timeout=120,
        )
        if r.returncode != 0:
            return "client exit=%d" % r.returncode
        return check_report(report_out, scenario, audit)
    except subprocess.TimeoutExpired:
        return "client timeout"
    finally:
        proc.kill()
        proc.wait()


if os.path.isfile(CLIENT) and not failures:
    # --- visible artifact: /app/report.json from the reference run ---
    if not os.path.isfile("/app/report.json"):
        failures.append("missing /app/report.json")
    else:
        audit = "/tmp/quartz_ferry_visible_audit.jsonl"
        if os.path.exists(audit):
            os.remove(audit)
        proc, port = start_origin("/app/ref_scenario.json", audit)
        if proc is None:
            failures.append("reference origin failed to start")
        else:
            try:
                url = "http://127.0.0.1:%d/api/challenge" % port
                urllib.request.urlopen(url, timeout=1).read()
            except Exception:
                pass
            finally:
                proc.kill()
                proc.wait()
        try:
            with open("/app/report.json") as fh:
                got = json.load(fh)
            with open("/tests/expected.json") as fh:
                want = json.load(fh)
            for k, v in want.items():
                if got.get(k) != v:
                    failures.append("report.json field %r mismatch" % k)
        except Exception as exc:
            failures.append("report.json unreadable: %s" % exc)

    # --- re-execute the client on a fresh reference origin ---
    err = run_case("/app/ref_scenario.json", "/app/ref_passfile.txt",
                   "grid-user", "/tmp/quartz_ferry_vis_report.json", "vis")
    if err:
        failures.append("visible re-run failed: %s" % err)

    # --- hidden deployments ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            need = [os.path.join(base, f) for f in
                    ("scenario.json", "passfile.txt", "expected.json")]
            if not all(os.path.isfile(p) for p in need):
                failures.append("hidden '%s' malformed" % c)
                continue
            with open(need[2]) as fh:
                exp = json.load(fh)
            out = "/tmp/quartz_ferry_hidden_%s.json" % c
            err = run_case(need[0], need[1], exp["user"], out, c)
            if err:
                failures.append("hidden case '%s' failed: %s" % (c, err))
                continue
            try:
                with open(out) as fh:
                    got = json.load(fh)
                for k, v in exp.items():
                    if got.get(k) != v:
                        failures.append(
                            "hidden '%s' report field %r mismatch" % (c, k))
            except Exception as exc:
                failures.append("hidden '%s' report unreadable: %s" % (c, exc))

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
