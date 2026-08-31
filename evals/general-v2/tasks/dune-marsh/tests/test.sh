#!/bin/bash
# Verifier for dune-marsh: re-runs the deliverable script, verifies the hash
# wiring in the visible config and auth_hash.txt, then EXECUTES the deliverable
# enable_auth.sh against every hidden config and boots fresh gateways to probe
# 401/200 behaviour. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the provided read-only fixture (no-modify rule).
PRISTINE_SERVICE_SHA="24c2cdcfd93f2e1a48ce1996e3b75d483ee7130787af07bbf28db1a31b1ea962"

fail_flag=0
if [ ! -f /app/gateway_service.py ]; then
    echo "no-modify: /app/gateway_service.py missing" >&2
    fail_flag=1
else
    actual="$(sha256sum /app/gateway_service.py | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_SERVICE_SHA" ]; then
        echo "no-modify: /app/gateway_service.py was modified" >&2
        fail_flag=1
    fi
fi

if [ ! -f /app/enable_auth.sh ] || [ ! -x /app/enable_auth.sh ]; then
    echo "FIELD: /app/enable_auth.sh missing or not executable" >&2
    fail_flag=1
fi
if [ ! -f /app/auth_hash.txt ]; then
    echo "FIELD: /app/auth_hash.txt missing" >&2
    fail_flag=1
fi

# Idempotent re-run of the primary deliverable from the current state.
if ! bash /app/enable_auth.sh >/tmp/enable_auth_rerun.log 2>&1; then
    echo "FIELD: enable_auth.sh re-run exited non-zero; tail:" >&2
    tail -4 /tmp/enable_auth_rerun.log | sed 's/^/  /' >&2
    fail_flag=1
fi

python3 - "$fail_flag" <<'PY'
import hashlib, json, os, shutil, subprocess, sys, tempfile, time, urllib.error, urllib.request

SECRET = "SableKey-68North"
SERVICE = "/app/gateway_service.py"
ENABLE = "/app/enable_auth.sh"
failures = []
if int(sys.argv[1]):
    failures.append("deliverables missing/not executable or fixture modified")


def boot_gateway(config_path, port):
    try:
        p = subprocess.Popen(
            [sys.executable, SERVICE, "--serve", "--config", config_path,
             "--port", str(port)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        return None
    for _ in range(100):
        if p.poll() is not None:
            return None
        try:
            urllib.request.urlopen(
                "http://127.0.0.1:%d/api/health" % port, timeout=2)
            # any HTTP response (200 or 401) means it is up
            return p
        except urllib.error.HTTPError:
            return p
        except Exception:
            time.sleep(0.1)
    try:
        p.kill()
    except Exception:
        pass
    return None


def probe(port, token):
    """Return (http_status, body_or_None) for /api/health."""
    req = urllib.request.Request("http://127.0.0.1:%d/api/health" % port)
    if token is not None:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.load(e)
        except Exception:
            return e.code, None
    except Exception:
        return None, None


def hash_parts(h):
    """Parse and structurally validate a password hash; return (salt, dk, iters)."""
    assert isinstance(h, str), "password_hash not a string"
    parts = h.split("$")
    assert len(parts) == 4 and parts[0] == "pbkdf2_sha256", \
        "hash not in pbkdf2_sha256$iter$salt$dk format"
    iters = int(parts[1])
    salt = bytes.fromhex(parts[2])
    dk = bytes.fromhex(parts[3])
    assert iters >= 1, "iteration count must be positive"
    assert len(salt) >= 8, "salt shorter than 8 bytes"
    assert len(dk) == 32, "derived key must be 32 bytes"
    return salt, dk, iters


def probe_gateway(config_path, port):
    p = boot_gateway(config_path, port)
    if p is None:
        return "gateway failed to boot"
    try:
        st, _ = probe(port, None)
        if st != 401:
            return "missing token: expected 401, got %r" % st
        st, _ = probe(port, SECRET + "-tampered")
        if st != 401:
            return "wrong token: expected 401, got %r" % st
        st, body = probe(port, SECRET)
        if st != 200 or not isinstance(body, dict) or body.get("status") != "ok":
            return "correct token: expected 200/ok, got %r %r" % (st, body)
        if body.get("auth_required") is not True:
            return "gateway reports auth_required=%r" % body.get("auth_required")
        return None
    finally:
        try:
            p.kill()
            p.wait(timeout=10)
        except Exception:
            pass


# ---------- visible config ----------
try:
    with open("/app/gateway/config.json") as f:
        cfg = json.load(f)
    auth = cfg["auth"]
    assert auth.get("enabled") is True, "auth.enabled is not true"
    assert auth.get("scheme") == "pbkdf2_sha256", "auth.scheme changed"
    iters = auth.get("iterations")
    assert isinstance(iters, int) and iters >= 1, "bad auth.iterations"
    h = auth.get("password_hash")
    if h is None:
        # fall back to the auth_hash.txt deliverable for wiring evidence
        raise AssertionError("password_hash not installed in config")
    salt, dk, hit = hash_parts(h)
    assert hit == iters, "hash iterations %d != config %d" % (hit, iters)
    good = hashlib.pbkdf2_hmac("sha256", SECRET.encode("utf-8"), salt, iters)
    bad = hashlib.pbkdf2_hmac("sha256", (SECRET + "x").encode("utf-8"),
                              salt, iters)
    assert good == dk, "config hash does not verify the secret"
    assert bad != dk, "config hash accepts a wrong secret"
except Exception as e:
    failures.append("visible config: %s" % e)

# ---------- auth_hash.txt ----------
try:
    with open("/app/auth_hash.txt") as f:
        line = f.read().strip()
    assert len(line.splitlines()) == 1, "auth_hash.txt must be a single line"
    salt, dk, iters = hash_parts(line)
    good = hashlib.pbkdf2_hmac("sha256", SECRET.encode("utf-8"), salt, iters)
    bad = hashlib.pbkdf2_hmac("sha256", (SECRET + "y").encode("utf-8"),
                              salt, iters)
    assert good == dk, "auth_hash.txt does not verify the secret"
    assert bad != dk, "auth_hash.txt accepts a wrong secret"
except Exception as e:
    failures.append("auth_hash.txt: %s" % e)

# ---------- probe a fresh gateway on the visible config ----------
try:
    with open("/app/gateway/config.json") as f:
        cfg = json.load(f)
    assert cfg["auth"]["enabled"] is True, "visible config still has auth off"
    err = probe_gateway("/app/gateway/config.json", 8517)
    if err:
        failures.append("visible gateway: %s" % err)
except Exception as e:
    failures.append("visible gateway probe: %s" % e)

# ---------- hidden cases: fresh configs, run enable_auth.sh on each ----------
hidden_dir = "/tests/hidden"
try:
    cases = sorted(os.listdir(hidden_dir)) if os.path.isdir(hidden_dir) else []
    assert cases, "no hidden cases present"
except Exception as e:
    cases = []
    failures.append("hidden cases: %s" % e)

for i, c in enumerate(cases):
    src = os.path.join(hidden_dir, c, "config.json")
    if not os.path.isfile(src):
        failures.append("hidden '%s': no config.json" % c)
        continue
    work = tempfile.mkdtemp(prefix="dm_%s_" % c)
    dst = os.path.join(work, "config.json")
    try:
        shutil.copyfile(src, dst)
        r = subprocess.run([ENABLE, dst], capture_output=True, text=True,
                           timeout=60)
        if r.returncode != 0:
            failures.append("hidden '%s': enable_auth.sh exited %d"
                            % (c, r.returncode))
            continue
        with open(dst) as f:
            cfg = json.load(f)
        auth = cfg["auth"]
        if not (auth.get("enabled") is True and isinstance(
                auth.get("password_hash"), str)):
            failures.append("hidden '%s': auth not enabled after script" % c)
            continue
        port = 8600 + i
        err = probe_gateway(dst, port)
        if err:
            failures.append("hidden '%s': %s" % (c, err))
    except Exception as e:
        failures.append("hidden '%s': %s" % (c, e))
    finally:
        shutil.rmtree(work, ignore_errors=True)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
