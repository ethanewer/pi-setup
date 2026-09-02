#!/bin/bash
# Verifier for gale-fathom. EXECUTES the deliverable /app/provision.sh from a
# pristine state and then from several genuinely different pre-existing states
# (stale/wrong-pin venv, wrong-python conda env, missing web/ssh services,
# missing uv project + shell init), and after EVERY run checks the full
# platform spec: pinned venv with a runnable CLI, correct function values,
# pinned miniconda + a specific-python conda env whose functions pass under
# `conda run`, non-interactive git/web/ssh, a self-contained uv project plus
# bash/zsh activation, and /app/pinned.txt matching the installed pins.
# Writes REWARD (0/1) to /logs/verifier/reward.txt; runs as root.
set -u

mkdir -p /logs/verifier
reward=0
BASE=/app

# ---------------------------------------------------------------------------
# Embedded standalone spec checker. Prints SPEC-OK and exits 0 iff every check
# passes. Otherwise prints per-check failures and exits 1.
# ---------------------------------------------------------------------------
cat > /tmp/verify_spec.py <<'PY'
import os, subprocess, sys, time, urllib.request

BASE = "/app"
fail = []

def run(cmd, timeout=120):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)

def check(name, ok, detail=""):
    if not ok:
        fail.append("%s: %s" % (name, detail) if detail else name)

def cur(cmd, timeout=120):
    r = run(cmd, timeout=timeout)
    return r.returncode == 0, (r.stdout + r.stderr).strip()

# ---- 1. venv deliverable: pinned fathom_core + runnable CLI -----------------
# Execute the venv deliverable at its literal path /app/env/.venv:
V = "/app/env/.venv/bin/python"
check("venv interpreter exists", os.path.isfile(V) and os.access(V, os.X_OK))
if os.path.isfile(V) and os.access(V, os.X_OK):
    r = run([V, "-c",
             "import fathom_core, gale_math;"
             "print(fathom_core.__version__, gale_math.__version__)"])
    got = r.stdout.strip().split()
    check("venv imports+versions", r.returncode == 0 and len(got) == 2,
          (r.stdout + r.stderr).strip())
    if len(got) == 2:
        check("venv fathom_core==2.4.0 pinned", got[0] == "2.4.0", got[0])
        check("venv gale_math dep==0.6.1", got[1] == "0.6.1", got[1])

    r = run([V, "-c",
             "import fathom_core;assert fathom_core.depth_scale(7,5)==[116,333,938,571,640],fathom_core.depth_scale(7,5);"
             "assert fathom_core.depth_scale(3,6)==[432,161,702,495,980,989];"
             "assert fathom_core.depth_scale(11,4)==[800,505,174,999];print('ok')"])
    check("venv depth_scale correctness", r.returncode == 0,
          (r.stdout + r.stderr).strip())

    cli = "/app/env/.venv/bin/fathom-cli"
    check("fathom-cli entry point exists",
          os.path.isfile(cli) and os.access(cli, os.X_OK))
    if os.path.isfile(cli):
        r = run([cli, "--seed", "7", "--n", "5"])
        check("fathom-cli output", r.returncode == 0 and r.stdout.strip() == "116 333 938 571 640",
              (r.stdout + r.stderr).strip())

# ---- 2. pinned miniconda + conda env gale311 (python 3.11) ------------------
CB = os.path.join(BASE, "miniconda3/bin/conda")
check("miniconda installed", os.path.isfile(CB) and os.access(CB, os.X_OK))
if os.path.isfile(CB) and os.access(CB, os.X_OK):
    ok, ver = cur([CB, "--version"])
    check("miniconda pinned 24.9.2", ok and "24.9.2" in ver, ver)
    r = run([CB, "run", "-n", "gale311", "python", "-c",
             "import sys;print('%d.%d'%sys.version_info[:2])"])
    check("conda env python 3.11", r.returncode == 0 and r.stdout.strip() == "3.11",
          (r.stdout + r.stderr).strip())
    r = run([CB, "run", "-n", "gale311", "python", "-c",
             "import fathom_core;assert fathom_core.depth_scale(7,5)==[116,333,938,571,640];print('ok')"])
    check("conda run functional check", r.returncode == 0,
          (r.stdout + r.stderr).strip())

# ---- 3. non-interactive git + web + ssh --------------------------------------
ok, which = cur(["bash", "-c", "command -v git; command -v nginx; command -v sshd"])
g, ws, ssh = ok and "git" in which, ok and "nginx" in which, ok and "sshd" in which
check("git present", g, which)
check("nginx installed", ws, which)
check("openssh-server installed", ssh, which)

nginx_conf = os.path.join(BASE, "nginx-fathom.conf")
check("nginx conf exists", os.path.isfile(nginx_conf))
ok, out = cur(["/usr/sbin/nginx", "-t", "-c", nginx_conf])
check("nginx config valid", ok, out)
marker = "gale-fathom online"
http_ok = False
deadline = time.time() + 30
while time.time() < deadline:
    try:
        with urllib.request.urlopen("http://127.0.0.1:8091/marker.html", timeout=3) as resp:
            if resp.read().decode().strip() == marker:
                http_ok = True
                break
    except Exception:
        pass
    time.sleep(2)
check("nginx serves marker on :8091", http_ok)

ok, out = cur(["/usr/sbin/sshd", "-t"])
check("sshd config valid", ok, out)

# ---- 4. self-contained uv project + shell auto-activation --------------------
for p in ("/app/fathom/pyproject.toml", "/app/fathom/uv.lock"):
    check("uv %s exists" % os.path.basename(p), os.path.isfile(p))
ok, out = cur(["/bin/bash", "-lc",
               "cd /app/fathom && uv run python -c \"import fathom_core;assert fathom_core.depth_scale(7,5)==[116,333,938,571,640];print('ok')\""])
check("uv project resolves+validates", ok, out)

for rc in ("/root/.bashrc", "/root/.zshrc"):
    try:
        txt = open(rc).read()
    except Exception:
        txt = ""
    check("%s activates gale311" % rc, "conda activate gale311" in txt)

# ---- 5. pinned.txt matches installed venv ------------------------------------
lock = os.path.join(BASE, "pinned.txt")
check("pinned.txt exists", os.path.isfile(lock))
if os.path.isfile(lock):
    lt = open(lock).read()
    for pin in ("fathom_core==2.4.0", "gale_math==0.6.1"):
        check("pinned.txt contains %s" % pin, pin in lt, lt)
    if os.path.isfile(V):
        r = run(["/app/env/.venv/bin/pip", "freeze"])
        frozen = r.stdout if r.returncode == 0 else ""
        for pin in ("fathom_core==2.4.0", "gale_math==0.6.1"):
            check("installed matches %s" % pin, pin in frozen)

if fail:
    for f in fail:
        print("SPEC-FAIL: " + f)
    sys.exit(1)
print("SPEC-OK")
sys.exit(0)
PY

# ---------------------------------------------------------------------------
# run_case: run the real deliverable and check the full spec.
# ---------------------------------------------------------------------------
run_case() {
    local label="$1"
    if [ ! -f "$BASE/provision.sh" ]; then
        echo "FAIL[$label]: /app/provision.sh missing"
        return 1
    fi
    if ! bash "$BASE/provision.sh" >/tmp/prov.log 2>&1; then
        echo "FAIL[$label]: provision.sh exit != 0: $(tail -2 /tmp/prov.log 2>/dev/null)"
        return 1
    fi
    if ! python3 /tmp/verify_spec.py; then
        return 1
    fi
    echo "OK[$label]"
    return 0
}

all_ok=1

# Visible case: fresh container run of the deliverable, then full spec.
run_case "visible" || all_ok=0

# Hidden cases: each is a genuinely different pre-existing filesystem/package
# state; provision.sh must repair it and the full spec must pass again.
if [ -d /tests/hidden ]; then
    for c in $(ls /tests/hidden); do
        seed="/tests/hidden/$c/seed.sh"
        if [ ! -f "$seed" ]; then
            echo "FAIL[hidden/$c]: missing seed.sh"
            all_ok=0
            continue
        fi
        if ! bash "$seed" >/tmp/seed_$c.log 2>&1; then
            echo "FAIL[hidden/$c]: seed failed: $(tail -1 /tmp/seed_$c.log 2>/dev/null)"
            all_ok=0
            continue
        fi
        run_case "hidden/$c" || all_ok=0
    done
else
    echo "FAIL: no /tests/hidden directory"
    all_ok=0
fi

[ "$all_ok" -eq 1 ] && reward=1
echo "$reward" > /logs/verifier/reward.txt
exit 0
