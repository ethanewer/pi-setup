#!/bin/bash
# Verifier for elm-ridge. EXECUTES the deliverable /app/provision.sh from several
# pre-existing filesystem states (fresh, partial, stale, corrupt) and, after each
# run, checks the full workspace spec: both 3.12 venvs, pinned installs from the
# local index, the data-library upgrade, gRPC bindings + chain_query, the Jupyter
# server, and /app/requirements.lock matching the installed pins.
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0
BASE=/app

# ---------------------------------------------------------------------------
# Embedded standalone spec checker. Prints "SPEC-OK" and exits 0 iff every
# check passes; otherwise prints per-check failures and exits 1.
# ---------------------------------------------------------------------------
cat > /tmp/verify_spec.py <<'PY'
import os, subprocess, sys, time, urllib.request

BASE = "/app"
AN = os.path.join(BASE, "venvs/analytics/bin/python")
SR  = os.path.join(BASE, "venvs/server/bin/python")
fail = []

def run(cmd, timeout=60):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)

def check(name, ok, detail=""):
    if not ok:
        fail.append("%s: %s" % (name, detail) if detail else name)

# --- 1. both venvs exist with a 3.12 interpreter (venv-at-path) ------------
for label, p in (("analytics", AN), ("server", SR)):
    check("interpreter exists %s" % label,
          os.path.isfile(p) and os.access(p, os.X_OK))
    if os.path.isfile(p) and os.access(p, os.X_OK):
        r = run([p, "-c", "import sys; print('.'.join(map(str, sys.version_info[:2])))"])
        check("python version %s" % label,
              r.returncode == 0 and r.stdout.strip() == "3.12",
              (r.stdout + r.stderr).strip())

def an_code(prog):
    return run([AN, "-c", prog])

# --- 2. analytics pinned installs + functions ------------------------------
if os.path.isfile(AN):
    r = an_code("import ridgekit,ridgemath,sidereal,ridgedf;"
                "print(ridgekit.__version__, ridgemath.__version__, "
                "sidereal.__version__, ridgedf.__version__)")
    got = r.stdout.strip().split()
    check("analytics imports+versions", r.returncode == 0 and len(got) == 4,
          (r.stdout + r.stderr).strip())
    if len(got) == 4:
        check("ridgekit pin 3.1.4", got[0] == "3.1.4", got[0])
        check("ridgemath pin 0.9.2", got[1] == "0.9.2", got[1])
        check("sidereal pin 0.2.1", got[2] == "0.2.1", got[2])
        check("ridgedf upgraded >=2.0.0", got[3].startswith("2."), got[3])

    r = an_code("import ridgekit;"
                "assert ridgekit.sample.score(7,5)==[442,525,760,459,798], ridgekit.sample.score(7,5);"
                "assert ridgekit.sample.score(3,6)==[286,985,84,399,866,381];print('ok')")
    check("ridgekit.sample.score correctness", r.returncode == 0, (r.stdout + r.stderr).strip())

    r = an_code("import sidereal;"
                "assert sidereal.bearing(2,30)=='090deg';"
                "assert sidereal.bearing(18,7)=='105deg';print('ok')")
    check("sidereal.bearing values", r.returncode == 0, (r.stdout + r.stderr).strip())

    badtime_code = ("import sidereal\n"
                    "for h,m in [(25,0),(0,75),(-1,10),(12,99)]:\n"
                    "    try:\n"
                    "        sidereal.bearing(h,m)\n"
                    "        raise SystemExit('no-raise')\n"
                    "    except ValueError:\n"
                    "        pass\n"
                    "print('ok')\n")
    r = an_code(badtime_code)
    check("sidereal.bearing raises ValueError on bad time",
          r.returncode == 0, (r.stdout + r.stderr).strip())

    r = an_code("import ridgedf;"
                "t=ridgedf.load([{'region':'n','team':'a'},{'region':'n','team':'b'},{'region':'s','team':'a'}]);"
                "k=sorted(t.groupby('region',collapse=True).keys());"
                "assert k==['n','s'], k;print('ok')")
    check("ridgedf collapse keyword works (upgrade)", r.returncode == 0,
          (r.stdout + r.stderr).strip())

    cli = os.path.join(BASE, "venvs/analytics/bin/ridge-cli")
    check("ridge-cli entry point exists", os.path.isfile(cli) and os.access(cli, os.X_OK))
    if os.path.isfile(cli):
        r = run([cli, "--seed", "7", "--n", "5"])
        check("ridge-cli output", r.returncode == 0 and r.stdout.strip() == "442 525 760 459 798",
              (r.stdout + r.stderr).strip())

# --- 3. server: chain_query + gRPC bindings from /app/chain.proto ----------
if os.path.isfile(SR):
    r = run([SR, "-c", "import chain_pb2, chain_pb2_grpc;"
                       "q=chain_pb2.QueryRequest(chain_id='x', n=2);"
                       "assert q.chain_id=='x' and q.n==2;"
                       "assert hasattr(chain_pb2_grpc,'ChainServiceStub');print('ok')"])
    check("gRPC bindings generated+importable", r.returncode == 0, (r.stdout + r.stderr).strip())

    r = run([SR, "-c", "import chain_query;"
                       "assert chain_query.resolve('alpha',3)=='417df61560d67c61', chain_query.resolve('alpha',3);"
                       "assert chain_query.resolve('beta',1)=='05e3bc756e005c1b';print('ok')"])
    check("chain_query.resolve correctness", r.returncode == 0, (r.stdout + r.stderr).strip())

# --- 4. Jupyter notebook server answers on 127.0.0.1:8899 ------------------
cfg = os.path.join(BASE, "jupyter_config.py")
check("jupyter config exists", os.path.isfile(cfg))
if os.path.isfile(cfg):
    try:
        txt = open(cfg).read()
    except Exception:
        txt = ""
    for needle in ("c.ServerApp.port = 8899", "c.ServerApp.ip",
                   "c.ServerApp.open_browser = False", "c.ServerApp.allow_root = True"):
        check("jupyter config contains %r" % needle, needle in txt)

    if os.path.isfile(AN):
        proc = subprocess.Popen(
            [AN, "-m", "jupyter", "notebook", "--config=" + cfg, "--no-browser"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        server_ok = False
        try:
            deadline = time.time() + 45
            while time.time() < deadline:
                if proc.poll() is not None:
                    break
                try:
                    with urllib.request.urlopen("http://127.0.0.1:8899/", timeout=3) as resp:
                        code = resp.getcode()
                        server_ok = code in (200, 302)
                        break
                except Exception:
                    time.sleep(2)
            check("jupyter server answers on 8899", server_ok)
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except Exception:
                proc.kill()

# --- 5. requirements.lock matches the installed analytics pins --------------
lock = os.path.join(BASE, "requirements.lock")
check("requirements.lock exists", os.path.isfile(lock))
if os.path.isfile(lock):
    try:
        lt = open(lock).read()
    except Exception:
        lt = ""
    for pin in ("ridgekit==3.1.4", "ridgemath==0.9.2", "sidereal==0.2.1", "ridgedf==2.1.0"):
        check("lock contains %s" % pin, pin in lt)
    if os.path.isfile(AN):
        r = run([os.path.join(BASE, "venvs/analytics/bin/pip"), "freeze"])
        frozen = r.stdout if r.returncode == 0 else ""
        for pin in ("ridgekit==3.1.4", "ridgemath==0.9.2", "sidereal==0.2.1", "ridgedf==2.1.0"):
            check("installed matches %s" % pin, pin in frozen)

if fail:
    for f in fail:
        print("SPEC-FAIL: " + f)
    sys.exit(1)
print("SPEC-OK")
sys.exit(0)
PY

# ---------------------------------------------------------------------------
# Run provision.sh once and run the spec checker.
# ---------------------------------------------------------------------------
run_case() {
    local label="$1"
    local key
    key="$(echo "$label" | tr '/' '_')"
    if [ ! -f "$BASE/provision.sh" ]; then
        echo "FAIL[$label]: /app/provision.sh missing"
        return 1
    fi
    if ! bash "$BASE/provision.sh" >/tmp/prov_$key.log 2>&1; then
        echo "FAIL[$label]: provision.sh exited non-zero: $(tail -1 /tmp/prov_$key.log 2>/dev/null)"
        return 1
    fi
    if ! python3 /tmp/verify_spec.py; then
        return 1
    fi
    echo "OK[$label]"
    return 0
}

all_ok=1

# Visible case: pristine (wipe /app/venvs), then provision and check.
rm -rf "$BASE/venvs"
run_case "visible" || all_ok=0

# Hidden cases: each is a genuinely different pre-existing filesystem state.
if [ -d /tests/hidden ]; then
    for c in $(ls /tests/hidden); do
        seed="/tests/hidden/$c/seed.sh"
        if [ ! -f "$seed" ]; then
            echo "FAIL[hidden/$c]: missing seed.sh"
            all_ok=0
            continue
        fi
        if ! bash "$seed" >/tmp/seed_$c.log 2>&1; then
            echo "FAIL[hidden/$c]: seed failed: $(tail -1 /tmp/seed_$c.log)"
            all_ok=0
            continue
        fi
        run_case "hidden/$c" || all_ok=0
    done
else
    echo "FAIL: no /tests/hidden directory"
    all_ok=0
fi

if [ "$all_ok" -eq 1 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
