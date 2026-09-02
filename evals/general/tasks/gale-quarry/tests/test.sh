#!/bin/bash
# Verifier for gale-quarry: executes the agent driver (launch.py) on the
# visible scenario and on every hidden scenario, validates result.json,
# re-runs both binaries independently, and inspects the OpenMP binary for
# genuine threading. Writes 1.0/0.0 to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0.0

PRISTINE_INI_SHA="4b99330b540f730072f87bb5705071adb7c37073d38034f127aa35fc5138ae08"

ini_ok=0
if [ -f /app/scenario.ini ]; then
    actual="$(sha256sum /app/scenario.ini | awk '{print $1}')"
    if [ "$actual" = "$PRISTINE_INI_SHA" ]; then ini_ok=1; fi
fi

python3 - "$ini_ok" <<'PY'
import json, os, shutil, subprocess, sys, tempfile

ini_ok = int(sys.argv[1])
failures = []
if not ini_ok:
    failures.append("/app/scenario.ini modified or missing (no-modify rule)")

BIN_S = "/app/bin/motes_serial"
BIN_O = "/app/bin/motes_openmp"


def parse_ini(path):
    cfg = {"N": 2000, "STEPS": 20, "SEED": 1, "MOTION": 0}
    try:
        for raw in open(path):
            line = raw.split("#", 1)[0].strip()
            if not line or "=" not in line:
                continue
            k, v = line.split("=", 1)
            k = k.strip().upper()
            v = v.strip()
            if k in cfg and v != "":
                cfg[k] = int(v)
    except Exception:
        pass
    return cfg


def sh(cmd, timeout=280):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def run_binary(binary, n, steps, seed, outbin):
    r = sh([binary, str(n), str(steps), str(seed), outbin])
    if r.returncode != 0:
        return None, "rc=%d %s" % (r.returncode, r.stderr[:200])
    fields = {}
    for line in r.stdout.splitlines():
        p = line.split()
        if len(p) == 2:
            fields[p[0]] = p[1]
    if not all(k in fields for k in ("TIME", "MOVE", "HASH")):
        return None, "missing TIME/MOVE/HASH in output"
    return fields, None


def check_openmp_genuine():
    try:
        r = subprocess.run(["nm", "-D", BIN_O], capture_output=True, text=True)
        if "GOMP_parallel" not in r.stdout:
            return "openmp binary lacks GOMP_parallel symbol (not genuinely threaded)"
        r2 = subprocess.run(["ldd", BIN_O], capture_output=True, text=True)
        if r2.returncode != 0 or "libgomp" not in r2.stdout:
            return "openmp binary is not linked against libgomp"
    except FileNotFoundError:
        return "nm/ldd unavailable"
    return None


def validate_result(res, cfg, tag):
    if not isinstance(res, dict):
        return "%s: result.json is not an object" % tag
    want_keys = {"task", "n", "steps", "seed", "serial_hash", "openmp_hash",
                 "match", "move", "serial_ms", "openmp_ms", "threads",
                 "openmp_linked", "ok"}
    if set(res.keys()) != want_keys:
        return "%s: result.json keys mismatch: %s" % (tag, sorted(res.keys()))
    if res.get("task") != "gale-quarry":
        return "%s: wrong task field" % tag
    if not res.get("match") or not res.get("openmp_linked") or not res.get("ok"):
        return "%s: ok/match/openmp_linked not all true" % tag
    if res.get("n") != cfg["N"] or res.get("steps") != cfg["STEPS"] or res.get("seed") != cfg["SEED"]:
        return "%s: n/steps/seed mismatch vs scenario.ini" % tag
    return None


def check_case(ini_path, tag):
    cfg = parse_ini(ini_path)
    n, steps, seed = cfg["N"], cfg["STEPS"], cfg["SEED"]

    # 1) execute the driver deliverable
    r = sh([sys.executable, "/app/launch.py", "run", os.path.dirname(ini_path) if os.path.dirname(ini_path) != "" else "/app"])
    # note: we always pass run-mode with the case dir explicitly
    if r.returncode != 0:
        return "%s: launch.py failed rc=%d: %s" % (tag, r.returncode, r.stderr[-300:])
    if not os.path.isfile("/app/result.json"):
        return "%s: launch.py did not write /app/result.json" % tag
    try:
        res = json.load(open("/app/result.json"))
    except Exception as e:
        return "%s: result.json unreadable: %s" % (tag, e)
    err = validate_result(res, cfg, tag)
    if err:
        return err

    # 2) re-run both binaries independently and compare
    fs, e1 = run_binary(BIN_S, n, steps, seed, "/tmp/gq_v_serial.bin")
    if fs is None:
        return "%s: serial binary failed: %s" % (tag, e1)
    fo, e2 = run_binary(BIN_O, n, steps, seed, "/tmp/gq_v_openmp.bin")
    if fo is None:
        return "%s: openmp binary failed: %s" % (tag, e2)
    if fs["HASH"] != fo["HASH"] or fs["MOVE"] != fo["MOVE"]:
        return "%s: serial and openmp physics disagree" % tag
    if fs["HASH"] != res.get("serial_hash") or fo["HASH"] != res.get("openmp_hash"):
        return "%s: result.json hashes do not match a fresh binary run" % tag
    try:
        if os.path.getsize("/tmp/gq_v_serial.bin") != 16 * n:
            return "%s: positions file is not 16*N bytes" % tag
    except Exception as e:
        return "%s: positions file unreadable: %s" % (tag, e)
    if cfg["MOTION"] == 1:
        try:
            if float(fs["MOVE"]) <= 0.0:
                return "%s: MOVE is not positive (no genuine motion)" % tag
        except Exception:
            return "%s: MOVE not a float" % tag
    try:
        if float(fo["TIME"]) <= 0.0:
            return "%s: openmp TIME is not positive" % tag
    except Exception:
        return "%s: openmp TIME not a float" % tag
    return None


# ---- 0) artifacts exist ----
for p in ("/app/src/motes.c", "/app/launch.py", BIN_S, BIN_O):
    if not os.path.isfile(p):
        failures.append("missing %s" % p)
if os.path.isfile(BIN_O):
    err = check_openmp_genuine()
    if err:
        failures.append(err)

# ---- 1) visible scenario ----
if os.path.isfile("/app/scenario.ini") and os.path.isfile("/app/launch.py") and os.path.isfile(BIN_O):
    err = check_case("/app/scenario.ini", "visible")
    if err:
        failures.append(err)

# ---- 2) hidden scenarios ----
hidden = "/tests/hidden"
if os.path.isdir(hidden):
    cases = sorted(d for d in os.listdir(hidden)
                   if os.path.isfile(os.path.join(hidden, d, "scenario.ini")))
    if len(cases) < 2:
        failures.append("expected >= 2 hidden scenarios")
    for c in cases:
        tmp = tempfile.mkdtemp(prefix="gq_case_")
        try:
            shutil.copy(os.path.join(hidden, c, "scenario.ini"),
                        os.path.join(tmp, "scenario.ini"))
            err = check_case(os.path.join(tmp, "scenario.ini"), "hidden/" + c)
            if err:
                failures.append(err)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
else:
    failures.append("no hidden cases")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1.0; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
