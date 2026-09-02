#!/usr/bin/env python3
"""Verifier for juniper-notch.

Starts a FRESH unauthenticated MQTT bus (mosquitto, loopback :31883) and a
FRESH survey gate (loopback :43979) on this container, then executes the
deliverable /app/q.py against (a) the agent's /app/job.json and (b) hidden
directives/maps under /tests/hidden, and validates:

  * the crafted directive, published retain=true onto the worker's inbox topic,
    is actually consumed by the relay worker and produces a receipt in
    /app/relay/applied/ whose digest matches a deterministic recomputation
    (proves the task was injected into the queue the worker consumes);
  * /app/roundtrip.out holds the *correct* SURVE site reply for the active map,
    derived live from the socket protocol + nearest-site computation.

This verifier is independent of the oracle's q.py internals: every expected
value is recomputed here from job/hidden inputs and from live responses of the
fixture gate/worker, never copied from the oracle.
"""
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import time

APP = "/app"
RELAY = os.path.join(APP, "relay")
APPLIED = os.path.join(RELAY, "applied")
HIDDEN = "/tests/hidden"

BROKER_CONF = os.path.join(RELAY, "broker.conf")
GATE_PORT = 43979
DEFAULT_MAP = os.path.join(RELAY, "maps", "default.json")

JOB_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
ALLOWED_SECTORS = {"north", "south", "east", "west"}

failures = []


def fail(msg):
    failures.append(msg)
    print("FAIL:", msg, flush=True)


def dig(job_id, sector, payload):
    s = "%s|%s|%s|%d" % (job_id, sector, ",".join(str(v) for v in payload),
                         len(payload))
    import hashlib
    return hashlib.sha256(s.encode()).hexdigest()[:16]


def validate_directive(d):
    if not isinstance(d, dict):
        return False
    job_id = d.get("job_id")
    kind = d.get("kind")
    sector = d.get("sector")
    payload = d.get("payload")
    if not isinstance(job_id, str) or not JOB_ID_RE.match(job_id):
        return False
    if kind != "rebalance":
        return False
    if sector not in ALLOWED_SECTORS:
        return False
    if not isinstance(payload, list) or not (1 <= len(payload) <= 12):
        return False
    if not all(isinstance(v, int) and not isinstance(v, bool)
               and 0 <= v <= 100000 for v in payload):
        return False
    return True


def kill_patterns():
    for pat in ("mosquitto -c /app/relay/broker.conf",
                "/app/relay/gate.py", "/app/relay/worker.py"):
        subprocess.run(["pkill", "-f", pat], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)


def start_broker():
    subprocess.Popen(["mosquitto", "-c", BROKER_CONF],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    # wait until an anonymous MQTT connect succeeds
    from paho.mqtt import client as mqtt
    deadline = time.time() + 8
    while time.time() < deadline:
        try:
            c = mqtt.Client(client_id="verif-probe")
            c.connect("127.0.0.1", 31883, keepalive=10)
            c.disconnect()
            return
        except Exception:
            time.sleep(0.2)
    raise RuntimeError("mosquitto did not come up")


def start_gate(mappath):
    subprocess.Popen([sys.executable, os.path.join(RELAY, "gate.py"), mappath],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.time() + 8
    while time.time() < deadline:
        try:
            s = socket.create_connection(("127.0.0.1", GATE_PORT), timeout=1)
            s.close()
            return
        except Exception:
            time.sleep(0.2)
    raise RuntimeError("gate did not come up")


def read_line(sock):
    buf = b""
    while not buf.endswith(b"\n"):
        c = sock.recv(1)
        if not c:
            break
        buf += c
    return json.loads(buf.decode("utf-8"))


def gate_survey_expected(mappath):
    """Connect live and determine the correct SURVE reply for `mappath`."""
    s = socket.create_connection(("127.0.0.1", GATE_PORT), timeout=8)
    s.settimeout(8)
    try:
        s.sendall(b"MAP\n")
        mp = read_line(s)
        target = mp["target"]

        def manhattan(site):
            return abs(site["row"] - target["row"]) + abs(site["col"] - target["col"])

        nearest = min(mp["sites"], key=lambda site: (manhattan(site), site["name"]))
        s.sendall(("SURVE %s\n" % nearest["name"]).encode("utf-8"))
        reply = read_line(s)
    finally:
        s.close()
    return reply


def run(cmd, timeout=40):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def wait_receipt(job_id, timeout=12):
    path = os.path.join(APPLIED, job_id + ".result.json")
    deadline = time.time() + timeout
    while time.time() < deadline:
        if os.path.exists(path):
            return path
        time.sleep(0.3)
    return None


def main():
    kill_patterns()
    time.sleep(0.3)
    start_broker()
    start_gate(DEFAULT_MAP)

    # ---- (0) validate the shipped directive file ----------------------------
    with open(os.path.join(APP, "job.json")) as fh:
        job = json.load(fh)
    if not validate_directive(job):
        fail("job.json is not a valid directive")
        return 1
    job_id = job["job_id"]
    rec_path = os.path.join(APPLIED, job_id + ".result.json")
    for p in __import__("glob").glob(os.path.join(APPLIED, "*.result.json")):
        try:
            os.remove(p)
        except OSError:
            pass

    # ---- (1) execute the deliverable: inject job + survey -------------------
    r = run([sys.executable, os.path.join(APP, "q.py")])
    if r.returncode != 0:
        fail("q.py (default run) exited %d: %s" % (r.returncode, r.stderr[-400:]))
        return 1

    # ---- (2) worker consumes the injected job -------------------------------
    worker = subprocess.Popen([sys.executable, os.path.join(RELAY, "worker.py")],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1.2)
    got = wait_receipt(job_id)
    if not got:
        fail("worker did not consume injected job %s" % job_id)
        _killp(worker)
        return 1
    rec = json.load(open(got))
    exp_dig = dig(job["job_id"], job["sector"], job["payload"])
    if rec.get("job_id") != job_id or rec.get("digest") != exp_dig:
        fail("receipt mismatch for %s (got %s, want digest %s)"
             % (job_id, rec.get("digest"), exp_dig))
        _killp(worker)
        return 1

    # ---- (3) roundtrip.out matches the live gate for the ACTIVE map --------
    try:
        ro = json.load(open(os.path.join(APP, "roundtrip.out")))
    except Exception as e:
        fail("roundtrip.out is not valid JSON: %r" % (e,))
        _killp(worker)
        return 1
    exp_survey = gate_survey_expected(DEFAULT_MAP)
    if (ro.get("site") != exp_survey.get("site")
            or ro.get("token") != exp_survey.get("token")
            or ro.get("row") != exp_survey.get("row")
            or ro.get("col") != exp_survey.get("col")):
        fail("roundtrip.out does not match live survey (site %s vs %s)"
             % (ro.get("site"), exp_survey.get("site")))
        _killp(worker)
        return 1

    # =========================== HIDDEN CASES ================================
    # H1: q.py must generalize to an unseen valid directive.
    h1 = json.load(open(os.path.join(HIDDEN, "h1_hidden_job.json")))
    h1id = h1["job_id"]
    r = run([sys.executable, os.path.join(APP, "q.py"), "publish",
             os.path.join(HIDDEN, "h1_hidden_job.json")])
    if r.returncode != 0:
        fail("q.py publish (H1) failed: %s" % r.stderr[-300:])
    else:
        got = wait_receipt(h1id)
        if not got:
            fail("H1: worker did not consume hidden job %s" % h1id)
        else:
            rec = json.load(open(got))
            exp = dig(h1["job_id"], h1["sector"], h1["payload"])
            if rec.get("digest") != exp:
                fail("H1: receipt digest mismatch for %s" % h1id)

    # H2: q.py survey must generalize to a different unseen map.
    kill_patterns()
    time.sleep(0.4)
    start_broker()   # fresh bus for clarity (retained cleared)
    start_gate(os.path.join(HIDDEN, "h2_map.json"))
    r = run([sys.executable, os.path.join(APP, "q.py"), "survey"])
    try:
        ro2 = json.load(open(os.path.join(APP, "roundtrip.out")))
    except Exception as e:
        fail("H2: roundtrip.out unreadable: %r" % (e,))
        ro2 = None
    if ro2 is not None:
        exp2 = gate_survey_expected(os.path.join(HIDDEN, "h2_map.json"))
        if (ro2.get("site") != exp2.get("site")
                or ro2.get("token") != exp2.get("token")
                or ro2.get("row") != exp2.get("row")
                or ro2.get("col") != exp2.get("col")):
            fail("H2: roundtrip.out does not match hidden map survey")

    # H3: a malformed directive must be rejected (no receipt), worker stays up.
    h3 = json.load(open(os.path.join(HIDDEN, "h3_malformed_job.json")))
    h3id = h3["job_id"]
    # the persistent worker from earlier may still be holding a connection on
    # the NEW broker; restart a clean worker, then publish the malformed job.
    _killp(worker)
    time.sleep(0.4)
    w2 = subprocess.Popen([sys.executable, os.path.join(RELAY, "worker.py")],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1.2)
    r = run([sys.executable, os.path.join(APP, "q.py"), "publish",
             os.path.join(HIDDEN, "h3_malformed_job.json")])
    time.sleep(2.5)
    bad_rec = os.path.join(APPLIED, h3id + ".result.json")
    if os.path.exists(bad_rec):
        fail("H3: malformed directive %s produced a receipt" % h3id)
    if w2.poll() is not None:
        fail("H3: worker crashed on a malformed directive")
    _killp(w2)

    _killp(worker)
    if failures:
        print("FAILURES: %d" % len(failures))
        return 1
    print("ALL CHECKS PASSED")
    return 0


def _killp(p):
    if p is None:
        return
    try:
        p.send_signal(signal.SIGKILL)
        p.wait(timeout=3)
    except Exception:
        pass


if __name__ == "__main__":
    sys.exit(main())