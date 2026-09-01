#!/bin/bash
# Verifier for basalt-tide: for the visible seed and every hidden seed it
# starts a fresh cipher daemon with an ephemeral (deleted) keyfile, EXECUTES
# /app/recover.py, and validates /app/recovery.json (seed, sbox, query
# budget, time budget). Writes 1.0/0.0 to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0.0

python3 - <<'PY'
import json, os, secrets, socket, subprocess, sys, time

sys.path.insert(0, "/app")

failures = []
if not os.path.isfile("/app/recover.py"):
    failures.append("missing /app/recover.py")

PORT = 46071
QLOG = "/tmp/.basalt_tide_queries"
MAX_QUERIES = 64
MAX_SECONDS = 60.0


def run_case(seed_int, seed_hex, tag):
    subprocess.run(["pkill", "-f", "cipher_service.py"], capture_output=True)
    time.sleep(0.4)
    if os.path.exists(QLOG):
        os.remove(QLOG)
    # ephemeral keyfile: daemon reads and deletes it at startup
    kf = "/tmp/.bt_key_%s" % secrets.token_hex(8)
    with open(kf, "w") as fh:
        fh.write(seed_hex + "\n")
    env = dict(os.environ)
    env["CIPHER_KEYFILE"] = kf
    proc = subprocess.Popen(
        [sys.executable, "/app/cipher_service.py", "--serve", "--port", str(PORT)],
        env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True)
    try:
        up = False
        for _ in range(100):
            try:
                s = socket.create_connection(("127.0.0.1", PORT), timeout=1)
                s.close()
                up = True
                break
            except OSError:
                time.sleep(0.1)
        if not up:
            return "daemon did not start"
        if os.path.exists(kf):
            return "daemon did not consume/delete the ephemeral keyfile"

        t0 = time.time()
        try:
            r = subprocess.run([sys.executable, "/app/recover.py"],
                               capture_output=True, text=True, timeout=90)
        except subprocess.TimeoutExpired:
            return "recover.py exceeded the hard 90s subprocess timeout"
        wall = time.time() - t0
        if r.returncode != 0:
            return "recover.py rc=%d: %s" % (r.returncode, r.stderr[-200:])
        if wall > MAX_SECONDS:
            return "over time budget (%.1fs)" % wall

        try:
            res = json.load(open("/app/recovery.json"))
        except Exception as e:
            return "recovery.json unreadable: %s" % e
        if not isinstance(res, dict):
            return "recovery.json is not an object"
        for k in ("task", "seed", "sbox", "queries", "elapsed_ms", "ok"):
            if k not in res:
                return "recovery.json missing key %r" % k
        if res.get("task") != "basalt-tide":
            return "wrong task field"
        if res.get("seed") != seed_hex:
            return "wrong seed: %r != %r" % (res.get("seed"), seed_hex)
        import cipher_service as eng
        want = bytes(eng.derive_sbox(seed_int))
        try:
            got = bytes.fromhex(res.get("sbox", ""))
        except Exception:
            return "sbox not hex"
        if got != want:
            return "wrong sbox"
        q = res.get("queries")
        if not isinstance(q, int) or q < 1 or q > MAX_QUERIES:
            return "reported queries %r outside 1..%d" % (q, MAX_QUERIES)
        if os.path.exists(QLOG):
            daemon_q = sum(1 for _ in open(QLOG))
        else:
            daemon_q = 0
        if daemon_q > MAX_QUERIES:
            return "daemon counted %d queries (budget %d)" % (daemon_q, MAX_QUERIES)
        if daemon_q < 1:
            return "no queries were made against the daemon"
        if res.get("ok") is not True:
            return "ok is not true"
        em = res.get("elapsed_ms")
        if not isinstance(em, int) or em < 0:
            return "elapsed_ms invalid"
        return None
    finally:
        try:
            proc.terminate()
        except Exception:
            pass
        subprocess.run(["pkill", "-f", "cipher_service.py"], capture_output=True)


# ---- visible case: seed from /app/.cipher_seed ----
try:
    seed_hex = open("/app/.cipher_seed").read().strip().lower()
    seed_int = int(seed_hex, 16)
except Exception as e:
    failures.append("visible seed file unreadable: %s" % e)
    seed_hex = None

if seed_hex is not None:
    if not (len(seed_hex) == 4 and 0 <= seed_int <= 0xFFFF):
        failures.append("visible seed malformed")
    else:
        err = run_case(seed_int, seed_hex, "visible")
        if err:
            failures.append("visible: " + err)

# ---- hidden cases ----
hidden = "/tests/hidden"
if os.path.isdir(hidden):
    seeds = sorted(f for f in os.listdir(hidden) if f.endswith(".seed"))
    if len(seeds) < 2:
        failures.append("expected >= 2 hidden seeds")
    for f in seeds:
        try:
            sh = open(os.path.join(hidden, f)).read().strip().lower()
            si = int(sh, 16)
            assert len(sh) == 4 and 0 <= si <= 0xFFFF
        except Exception as e:
            failures.append("hidden %s malformed: %s" % (f, e))
            continue
        err = run_case(si, sh, f)
        if err:
            failures.append("hidden %s: %s" % (f, err))
else:
    failures.append("no hidden cases")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1.0; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
