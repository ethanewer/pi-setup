#!/usr/bin/env bash
#
# Verifier for dunlin-shoal: checks the visible deliverables (/app/export.py,
# /app/snapshot.json), ENFORCES the no-modify and read-only rules, and EXECUTES
# /app/export.py on the visible compose fixture, on every hidden live stack
# (provisioned with its own cluster, credentials and port) and on an
# unreachable-port stack where the exporter must fail cleanly.
#
# The reward file is written on EVERY exit path.
set -u

mkdir -p /logs/verifier
printf 0 > /logs/verifier/reward.txt

# Keep the scenario live (idempotent infrastructure, in the image).
timeout 120 /opt/dunctl/dbctl.sh up >/dev/null 2>&1 || true

if python3 - <<'PY'
import json, os, pwd, shutil, subprocess, sys

SOLVE = "/app/export.py"
SNAPSHOT = "/app/snapshot.json"
VISIBLE_COMPOSE = "/app/deploy/compose.yaml"
PRISTINE_COMPOSE_SHA = "f36710c7736c377393fcddf30f795d5f7bd0b912174fcdaac22b68092b9e39c2"
SUPER_PW = "Supt-Dunlin-9931"
MAIN_PORT = 5533

PGBIN = "/usr/lib/postgresql/16/bin"
if not os.path.isdir(PGBIN):
    cands = sorted(p for p in __import__("glob").glob("/usr/lib/postgresql/*/bin"))
    PGBIN = cands[-1] if cands else PGBIN

failures = []


def psq(sql, port=MAIN_PORT, db="postgres", timeout=45):
    """Superuser query over TCP (md5)."""
    env = dict(os.environ, PGPASSWORD=SUPER_PW)
    return subprocess.run(
        [os.path.join(PGBIN, "psql"), "-h", "127.0.0.1", "-p", str(port),
         "-U", "postgres", "-d", db, "-tA", "-v", "ON_ERROR_STOP=1", "-c", sql],
        capture_output=True, text=True, timeout=timeout, env=env)


def su_pg(cmd, timeout=120):
    return subprocess.run(["su", "postgres", "-c", cmd],
                          capture_output=True, text=True, timeout=timeout)


def parse_compose(path):
    """Guarded minimal parser for the compose layout (same as the fixture's)."""
    env, port = {}, None
    in_services = False
    svc_indent = None
    in_env = in_ports = False
    with open(path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            body = "" if line.lstrip().startswith("#") else line.split("#", 1)[0]
            if not body.strip():
                continue
            ind = len(body) - len(body.lstrip(" "))
            content = body.strip()
            if content == "services:":
                in_services = True
                continue
            if in_services and ind == 0:
                in_services = False
            if in_services and ind == 2 and content.endswith(":"):
                in_env = in_ports = False
                continue
            if in_services and content in ("environment:",):
                in_env, in_ports = True, False
                continue
            if in_services and content in ("ports:",):
                in_env, in_ports = False, True
                continue
            if in_env and ":" in content:
                k, _, v = content.partition(":")
                env[k.strip()] = v.strip().strip('"').strip("'")
            elif in_ports and content.startswith("- "):
                spec = content[2:].strip().strip('"').strip("'")
                left = spec.split(":")[0].strip()
                if left.isdigit():
                    port = int(left)
    for key in ("POSTGRES_DB", "POSTGRES_USER", "POSTGRES_PASSWORD"):
        if not env.get(key):
            raise ValueError("compose missing %s" % key)
    if port is None:
        raise ValueError("compose missing published port")
    return env["POSTGRES_DB"], env["POSTGRES_USER"], env["POSTGRES_PASSWORD"], port


def run_exporter(compose, out):
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run([sys.executable, SOLVE, compose, out],
                           capture_output=True, text=True, timeout=120)
    except subprocess.TimeoutExpired:
        return None
    return r


try:
    expected = json.load(open("/tests/expected.json"))
except Exception as exc:
    print("visible expected unreadable: %s" % exc, file=sys.stderr)
    sys.exit(1)

# --- no-modify guard on the visible compose fixture -----------------------
try:
    import hashlib
    h = hashlib.sha256(open(VISIBLE_COMPOSE, "rb").read()).hexdigest()
    if h != PRISTINE_COMPOSE_SHA:
        failures.append("compose.yaml was modified (no-modify rule)")
except FileNotFoundError:
    failures.append("missing /app/deploy/compose.yaml")

# --- database untouched (read-only rule): pristine row count --------------
if not failures:
    r = psq("SELECT count(*) FROM sensor_readings", db=expected["database"])
    if r.returncode != 0:
        failures.append("tamper-check query failed: %s" % r.stderr.strip()[:200])
    else:
        try:
            if int(r.stdout.strip()) != expected["row_count"]:
                failures.append("visible database row count was modified")
        except ValueError:
            failures.append("tamper-check output unparsable")

# --- visible deliverable: /app/snapshot.json ------------------------------
if not failures:
    try:
        got = json.load(open(SNAPSHOT))
        if got != expected:
            failures.append("snapshot.json does not match visible expected")
    except FileNotFoundError:
        failures.append("missing /app/snapshot.json")
    except Exception as exc:
        failures.append("snapshot.json unreadable: %s" % exc)

# --- execute the deliverable on the visible compose ------------------------
if not failures:
    if not os.path.isfile(SOLVE):
        failures.append("missing /app/export.py")
    else:
        out = "/tmp/dunlin_visible_out.json"
        r = run_exporter(VISIBLE_COMPOSE, out)
        if r is None or r.returncode != 0:
            failures.append("export.py failed on visible compose: %s"
                            % (getattr(r, "stderr", "") or "")[:200])
        elif not os.path.isfile(out):
            failures.append("export.py created no output on visible compose")
        else:
            try:
                if json.load(open(out)) != expected:
                    failures.append("export.py visible-case output mismatch")
            except Exception:
                failures.append("export.py visible output unparsable")

# --- hidden cases ----------------------------------------------------------
hidden_dir = "/tests/hidden"
live = unreachable = 0
if os.path.isdir(hidden_dir):
    for name in sorted(os.listdir(hidden_dir)):
        base = os.path.join(hidden_dir, name)
        compose = os.path.join(base, "compose.yaml")
        if not os.path.isfile(compose):
            continue
        if failures:
            break
        try:
            db, user, pw, port = parse_compose(compose)
        except Exception as exc:
            failures.append("hidden '%s' compose unparsable: %s" % (name, exc))
            continue

        if os.path.isfile(os.path.join(base, "unreachable")):
            out = "/tmp/dunlin_badport_out.json"
            r = run_exporter(compose, out)
            if r is None:
                failures.append("hidden '%s': exporter hung" % name)
            elif r.returncode == 0:
                failures.append("hidden '%s': exporter should fail on unreachable port" % name)
            elif os.path.exists(out):
                failures.append("hidden '%s': output file must not be created on failure" % name)
            else:
                unreachable += 1
            continue

        # provision a live hidden cluster on the compose's published port
        if port == MAIN_PORT:
            failures.append("hidden '%s': hidden port collides with main" % name)
            continue
        data = "/tmp/pgcase_%s" % name
        shutil.rmtree(data, ignore_errors=True)
        os.makedirs(data)
        pguid = pwd.getpwnam("postgres").pw_uid
        os.chown(data, pguid, pguid)
        try:
            r = su_pg("%s/initdb -D %s -U postgres --auth-local=trust "
                      "--auth-host=md5 --no-locale -E UTF8" % (PGBIN, data))
            if r.returncode != 0:
                failures.append("hidden '%s': initdb failed" % name)
                continue
            r = su_pg("%s/pg_ctl -D %s -o '-p %d -h 127.0.0.1' -l %s/pg.log -w start"
                      % (PGBIN, data, port, data))
            if r.returncode != 0:
                failures.append("hidden '%s': cluster start failed" % name)
                continue
            chk = su_pg("%s/psql -p %d -d postgres -tA -c \"SELECT 1 FROM pg_roles "
                        "WHERE rolname = '%s'\"" % (PGBIN, port, user))
            if chk.returncode != 0 or chk.stdout.strip() != "1":
                r = su_pg("%s/psql -p %d -d postgres -v ON_ERROR_STOP=1 -q "
                          "-c \"ALTER USER postgres PASSWORD '%s'; CREATE ROLE %s LOGIN PASSWORD '%s'\""
                          % (PGBIN, port, SUPER_PW, user, pw))
            else:
                r = su_pg("%s/psql -p %d -d postgres -v ON_ERROR_STOP=1 -q "
                          "-c \"ALTER USER postgres PASSWORD '%s'\"" % (PGBIN, port, SUPER_PW))
            if r.returncode != 0:
                failures.append("hidden '%s': role provisioning failed: %s"
                                % (name, r.stderr.strip()[:200]))
                continue
            r = su_pg("%s/createdb -p %d -O %s %s" % (PGBIN, port, user, db))
            if r.returncode != 0:
                failures.append("hidden '%s': createdb failed: %s"
                                % (name, r.stderr.strip()[:200]))
                continue
            r = su_pg("%s/psql -p %d -d %s -v ON_ERROR_STOP=1 -q -f %s"
                      % (PGBIN, port, db, os.path.join(base, "seed.sql")))
            if r.returncode != 0:
                failures.append("hidden '%s': seed failed: %s"
                                % (name, r.stderr.strip()[:200]))
                continue
            r = su_pg("%s/psql -p %d -d %s -v ON_ERROR_STOP=1 -q "
                      "-c \"GRANT SELECT ON sensor_readings TO %s\""
                      % (PGBIN, port, db, user))

            exp_path = os.path.join(base, "expected.json")
            try:
                want = json.load(open(exp_path))
            except Exception as exc:
                failures.append("hidden '%s' expected unreadable: %s" % (name, exc))
                continue
            out = "/tmp/dunlin_hidden_%s.json" % name
            r = run_exporter(compose, out)
            if r is None or r.returncode != 0 or not os.path.isfile(out):
                failures.append("hidden '%s': export.py failed: %s"
                                % (name, (getattr(r, "stderr", "") or "")[:200]))
            else:
                try:
                    if json.load(open(out)) != want:
                        failures.append("hidden '%s': output mismatch" % name)
                except Exception:
                    failures.append("hidden '%s': output unparsable" % name)
        except subprocess.TimeoutExpired:
            failures.append("hidden '%s': timed out" % name)
        finally:
            subprocess.run(["su", "postgres", "-c",
                            "%s/pg_ctl -D %s -m fast stop" % (PGBIN, data)],
                           capture_output=True, timeout=60)
            shutil.rmtree(data, ignore_errors=True)
        live += 1

    if live < 2:
        failures.append("expected >=2 live hidden scenarios, saw %d" % live)
    if unreachable < 1:
        failures.append("expected >=1 unreachable-port scenario")
else:
    failures.append("no hidden cases directory")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY
then
  printf 1 > /logs/verifier/reward.txt
else
  printf 0 > /logs/verifier/reward.txt
fi
exit 0