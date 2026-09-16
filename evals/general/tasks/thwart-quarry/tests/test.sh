#!/bin/bash
# Verifier for thwart-quarry (executes-deliverable).
# Starts redis via the agent's /app/start_redis.sh, then drives concurrent
# cache-aside + single-flight + atomic-spend workloads from the visible
# fixture (/app/workloads/visible_case.json) and every hidden fixture under
# /tests/hidden, asserting exact per-key backend call counts, generation-fresh
# values, key TTL windows, and the no-lost-update spend invariant.
# Guarantee a reward on every exit path.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

if [ ! -f /app/cache_layer.py ]; then
  echo "missing deliverable /app/cache_layer.py" >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi
if [ ! -f /app/start_redis.sh ]; then
  echo "missing deliverable /app/start_redis.sh" >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi
if [ ! -f /app/workloads/visible_case.json ]; then
  echo "missing visible fixture /app/workloads/visible_case.json" >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

python3 - <<'PY'
import importlib.util
import json
import os
import random
import redis
import subprocess
import sys
import threading
import time

REWARD = "/logs/verifier/reward.txt"
failures = []


def fail(msg):
    failures.append(msg)


def hard_abort(msg):
    print(msg)
    sys.stdout.flush()
    with open(REWARD, "w") as fh:
        fh.write("0")
    os._exit(0)


def run_case(label, path):
    with open(path) as fh:
        cfg = json.load(fh)
    port = int(cfg["port"])
    ttl = float(cfg["ttl_seconds"])

    # 1) start redis from the agent's deliverable, then wait for PONG
    r = subprocess.run(["bash", "/app/start_redis.sh", str(port)],
                       capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        fail("%s: /app/start_redis.sh failed: %s" % (label, (r.stderr or r.stdout).strip()))
        return
    cli = redis.Redis(host="127.0.0.1", port=port, decode_responses=True,
                      socket_connect_timeout=2, socket_timeout=15)
    ready = False
    for _ in range(50):
        try:
            cli.ping()
            ready = True
            break
        except redis.RedisError:
            time.sleep(0.2)
    if not ready:
        fail("%s: redis never answered on port %d" % (label, port))
        return
    cli.flushdb()
    try:
        handle = MOD.open_cache(host="127.0.0.1", port=port)
    except Exception as exc:  # noqa: BLE001
        fail("%s: open_cache failed: %r" % (label, exc))
        return

    keys = sorted(cfg["values"].keys())
    readers = int(cfg["readers_per_key"])
    rounds = int(cfg["rounds"])
    latency = float(cfg["backend_latency_s"])

    class Backend(object):
        def __init__(self):
            self.values = {}
            self.calls = {}

        def get(self, key):
            self.calls[key] = self.calls.get(key, 0) + 1
            if latency:
                time.sleep(latency)
            return self.values[key]

    backend = Backend()

    # 2) concurrent-miss windows: exactly one backend call per key per round
    for rnd in range(1, rounds + 1):
        backend.values = {k: "%s#g%d" % (k, rnd) for k in keys}
        backend.calls = {}
        n = len(keys) * readers
        barrier = threading.Barrier(n)
        results = {k: [] for k in keys}
        errors = []

        def reader(k):
            try:
                barrier.wait()
                results[k].append(MOD.cached_get(handle, k, backend, ttl))
            except Exception as exc:  # noqa: BLE001
                errors.append((k, repr(exc)))

        threads = [threading.Thread(target=reader, args=(k,))
                   for k in keys for _ in range(readers)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=60)
            if t.is_alive():
                hard_abort("%s: reader thread hung in round %d (single-flight deadlock?)"
                           % (label, rnd))
        if errors:
            fail("%s: round %d reader thread errors: %s" % (label, rnd, errors[:5]))
            return
        for k in keys:
            for v in results[k]:
                if str(v) != backend.values[k]:
                    fail("%s: round %d key %s reader got %r, want %r (stale or wrong value)"
                         % (label, rnd, k, v, backend.values[k]))
            got = backend.calls.get(k, 0)
            if got != 1:
                fail("%s: round %d key %s backend calls = %d, want exactly 1"
                     % (label, rnd, k, got))
        # 3) keys must actually expire between rounds
        if rnd < rounds:
            still = {}
            for k in keys:
                deadline = time.time() + ttl + 30
                while time.time() < deadline:
                    try:
                        if cli.exists(k) == 0:
                            break
                    except redis.RedisError:
                        pass
                    time.sleep(0.05)
                try:
                    still[k] = cli.exists(k)
                except redis.RedisError:
                    still[k] = 1
            bad = [k for k, v in still.items() if v]
            if bad:
                fail("%s: keys %s did not expire before round %d"
                     % (label, bad, rnd + 1))
                return

    # 4) TTL windows after the last round
    for k in keys:
        try:
            t = cli.ttl(k)
        except redis.RedisError:
            fail("%s: ttl(%s) errored" % (label, k))
            continue
        if t < ttl - 2 or t > ttl + 1:
            fail("%s: ttl(%s)=%s outside [%d-2, %d+1]" % (label, k, t, int(ttl), int(ttl)))

    # 5) atomic compound read-modify-write: concurrent spends
    skey = cfg["spend_key"]
    start = int(cfg["spend_start"])
    cli.set(skey, start)
    workers = int(cfg["spend_workers"])
    ops = int(cfg["ops_per_worker"])
    amin, amax = int(cfg["amount_min"]), int(cfg["amount_max"])
    random.seed(port)
    acked = []
    lock = threading.Lock()
    spend_errors = []

    # The spend operations must actually be server-side Lua scripts on the
    # wire (EVAL/EVALSHA), not a Python-side read-check-write or a client
    # transaction. Observe the protocol with redis-cli MONITOR: a static
    # "eval"/"register_script" string in the source is spoofable and is
    # therefore only a fast-fail, not the enforcement. Attach BEFORE the
    # spend threads start so every command they issue is on the wire log.
    montag = "mon-%d-%s" % (port, label.replace("/", "_"))
    monlog = "/tmp/%s.log" % montag
    monf = open(monlog, "w")
    mon = subprocess.Popen(["redis-cli", "-p", str(port), "monitor"],
                           stdout=monf, stderr=subprocess.STDOUT, text=True)
    attached = False
    for _ in range(60):
        try:
            cli.ping()
        except redis.RedisError:
            pass
        if os.path.getsize(monlog) > 0:
            attached = True
            break
        time.sleep(0.2)

    def spender():
        try:
            for _ in range(ops):
                amt = random.randint(amin, amax)
                if MOD.spend(handle, skey, amt):
                    with lock:
                        acked.append(amt)
        except Exception as exc:  # noqa: BLE001
            with lock:
                spend_errors.append(repr(exc))

    sthreads = [threading.Thread(target=spender) for _ in range(workers)]
    for t in sthreads:
        t.start()
    for t in sthreads:
        t.join(timeout=180)
        if t.is_alive():
            hard_abort("%s: spend worker hung" % label)
    if spend_errors:
        fail("%s: spend thread errors: %s" % (label, spend_errors[:5]))
        return
    raw = cli.get(skey)
    final = int(raw) if raw is not None else 0
    total_acked = sum(acked)
    if final < 0:
        fail("%s: balance went negative (%d): lost update / overdraft" % (label, final))
    if start - total_acked != final:
        fail("%s: no-lost-update violated: start %d - acked %d = %d but final balance %d"
             % (label, start, total_acked, start - total_acked, final))
    monf.close()
    if attached:
        try:
            mon.kill()
        except Exception:  # noqa: BLE001
            pass
        try:
            wire = open(monlog).read().upper()
        except OSError:
            wire = ""
        if "\"EVAL\"" not in wire and "\"EVALSHA\"" not in wire:
            fail("%s: spend ran no server-side Lua script on the wire "
                 "(no EVAL/EVALSHA observed); atomicity must come from a "
                 "redis Lua script, not a Python or client-side transaction" % label)
    else:
        mon.kill()


# ---- load and sanity-check the deliverable module ----
try:
    spec = importlib.util.spec_from_file_location("cache_layer", "/app/cache_layer.py")
    MOD = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(MOD)
except Exception as exc:  # noqa: BLE001
    hard_abort("import of /app/cache_layer.py failed: %r" % (exc,))

for name in ("open_cache", "cached_get", "spend"):
    if not callable(getattr(MOD, name, None)):
        hard_abort("contract function missing from /app/cache_layer.py: %s" % name)

src = open("/app/cache_layer.py").read().lower()
if "register_script" not in src and "eval" not in src:
    hard_abort("cache_layer.py does not use server-side Lua scripting "
               "(no register_script / EVAL found)")

# ---- visible case ----
run_case("visible", "/app/workloads/visible_case.json")

# ---- hidden cases ----
hidden = sorted(n for n in os.listdir("/tests/hidden")
                if os.path.isdir(os.path.join("/tests/hidden", n)))
if len(hidden) < 2:
    hard_abort("expected >= 2 hidden cases, found %d" % len(hidden))
for case in hidden:
    p = os.path.join("/tests/hidden", case, "case.json")
    if not os.path.exists(p):
        fail("missing hidden fixture %s" % p)
        continue
    run_case(case, p)

if failures:
    print("FAILURES:")
    for m in failures:
        print("  - " + m)
    with open(REWARD, "w") as fh:
        fh.write("0")
    sys.exit(0)

print("ALL PASS: single-flight counts, TTL windows and atomic spend verified "
      "on visible + %d hidden cases" % len(hidden))
with open(REWARD, "w") as fh:
    fh.write("1")
sys.exit(0)
PY