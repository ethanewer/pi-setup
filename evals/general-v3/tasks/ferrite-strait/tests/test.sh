#!/bin/bash
# Verifier for tasks/ferrite-strait (executes-deliverable).
#
# For the default config and each hidden config it EXECUTES /app/launch.sh,
# then independently checks:
#   * the qemu process in the config's pidfile is alive and its cmdline really
#     runs the VM with the config's VNC display, -display none, -nic none and
#     the config's memory;
#   * the VNC port (5900 + vnc_display) and the web port are in the LISTEN
#     table (netstat/ss assertions) and the VNC port speaks RFB;
#   * the web page serves the status title + marker;
#   * /cgi-bin/status.json (installed from the /app/status.cgi deliverable)
#     reports LIVE state: qemu_pid == pidfile pid, alive == 1, vnc_port ==
#     5900 + display, and the config fields echoed correctly.
#
# Robustness: a numeric reward is ALWAYS written, even if this script is
# interrupted or the python body crashes. An internal deadline gates every
# blocking wait so a slow/hanging deliverable records 0 well before the
# harness verifier window instead of being killed silently.
set -u
mkdir -p /logs/verifier

__vfinal() { [ -f /logs/verifier/reward.txt ] || echo 0 > /logs/verifier/reward.txt; }
trap __vfinal EXIT
trap '__vfinal; exit 143' TERM INT

python3 -u - <<'PYEOF'
import json, os, re, signal, socket, subprocess, sys, time, urllib.request

failures = []
HALL = "/tests/hidden"
LAUNCH = "/app/launch.sh"
STATUS_CGI = "/app/status.cgi"

DEADLINE = time.time() + 240.0

def remaining():
    return max(2.0, DEADLINE - time.time())

def deadline_hit():
    return time.time() >= DEADLINE

def require(cond, msg):
    if not cond:
        failures.append(msg)

def run_launch(cfg_path):
    timeout = min(60.0, remaining())
    try:
        return subprocess.run(["bash", LAUNCH, cfg_path],
                              capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None

def kill_pidfile(pk):
    try:
        with open(pk) as f:
            pid = int(f.read().strip())
        os.kill(pid, signal.SIGKILL)
    except Exception:
        pass

def teardown(cfg):
    for key in ("pidfile", "web_pidfile"):
        if cfg.get(key):
            kill_pidfile(cfg[key])

def read_pidfile(pf):
    try:
        return int(open(pf).read().strip())
    except Exception:
        return None

def pid_alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except Exception:
        return False

def cmdline(pid):
    try:
        with open("/proc/%d/cmdline" % pid, "rb") as f:
            return f.read().decode("utf-8", "replace").split("\0")
    except Exception:
        return []

def listen_ports():
    """Parse TCP LISTEN ports from ss/netstat (guarded)."""
    for cmd in (["ss", "-ltn"], ["netstat", "-ltn"]):
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        except Exception:
            continue
        ports = set()
        for line in (r.stdout or "").splitlines():
            if "LISTEN" not in line and "LISTEN" not in (r.stdout or ""):
                continue
            if "LISTEN" not in line:
                continue
            m = re.search(r"[:.](\d+)\s", line.strip())
            if not m:
                m = re.search(r"[:.](\d+)\s+\S*$", line.strip())
            if m:
                ports.add(int(m.group(1)))
        if ports:
            return ports
    return None

def tcp_open(port, tries=1):
    for _ in range(tries):
        if deadline_hit():
            return False
        s = socket.socket()
        s.settimeout(0.8)
        try:
            if s.connect_ex(("127.0.0.1", port)) == 0:
                return True
        finally:
            s.close()
        time.sleep(0.4)
    return False

def rfb_greeting(port, tries=3):
    for _ in range(tries):
        if deadline_hit():
            return None
        s = None
        try:
            s = socket.socket()
            s.settimeout(2.0)
            s.connect(("127.0.0.1", port))
            data = s.recv(16)
            if data.startswith(b"RFB "):
                return data
        except Exception:
            pass
        finally:
            if s is not None:
                s.close()
        time.sleep(0.4)
    return None

def http_get(port, path, tries=3):
    for _ in range(tries):
        if deadline_hit():
            return None
        try:
            with urllib.request.urlopen("http://127.0.0.1:%d%s" % (port, path),
                                        timeout=2.0) as r:
                return r.read().decode("utf-8", "replace")
        except Exception:
            time.sleep(0.4)
    return None


# ---------------------------------------------------------------------------
# 1) Deliverables present + executable
# ---------------------------------------------------------------------------
for p in (LAUNCH, "/app/kiosk.conf", STATUS_CGI):
    require(os.path.exists(p), "missing deliverable %s" % p)
require(os.access(LAUNCH, os.X_OK), "/app/launch.sh not executable")
require(os.access(STATUS_CGI, os.X_OK), "/app/status.cgi not executable")
if not (os.path.exists(LAUNCH) and os.path.exists(STATUS_CGI)):
    print("fatal: missing core deliverables")
    open("/logs/verifier/reward.txt", "w").write("0")
    sys.exit(0)

# default config sanity: VNC display 1, standard web port 80
try:
    dc = json.load(open("/app/kiosk.conf"))
    require(int(dc.get("vnc_display", -1)) == 1, "kiosk.conf vnc_display must be 1")
    require(int(dc.get("web_port", -1)) == 80, "kiosk.conf web_port must be 80")
except Exception as e:
    failures.append("kiosk.conf unreadable: %r" % e)
    dc = None

# ---------------------------------------------------------------------------
# 2) execute launch.sh for the default + each hidden scenario
# ---------------------------------------------------------------------------
def run_scenario(label, cfg_path):
    try:
        cfg = json.load(open(cfg_path))
    except Exception as e:
        failures.append("%s: config unreadable: %r" % (label, e))
        return
    teardown(cfg)
    r = run_launch(cfg_path)
    if r is None:
        failures.append("%s: launch.sh timed out" % label)
        teardown(cfg)
        return
    if r.returncode != 0:
        failures.append("%s: launch.sh rc=%s stderr=%r"
                        % (label, r.returncode, (r.stderr or "")[-250:]))
        teardown(cfg)
        return

    disp = int(cfg["vnc_display"])
    vnc_port = 5900 + disp
    web_port = int(cfg["web_port"])
    mem = int(cfg.get("mem_mib", 256))

    ready = False
    for _ in range(30):
        if deadline_hit():
            break
        if (read_pidfile(cfg["pidfile"]) and tcp_open(vnc_port)
                and tcp_open(web_port)):
            ready = True
            break
        time.sleep(1)
    if not ready:
        failures.append("%s: kiosk never became ready (vnc %d web %d)"
                        % (label, vnc_port, web_port))
        teardown(cfg)
        return

    # pidfile -> live qemu with the right arguments
    pid = read_pidfile(cfg["pidfile"])
    require(pid is not None and pid > 0, "%s: bad pidfile" % label)
    if pid:
        require(pid_alive(pid), "%s: background qemu pid not alive" % label)
        argv = cmdline(pid)
        if argv:
            joined = " ".join(argv)
            require("-vnc" in argv and (":%d" % disp) in argv,
                    "%s: qemu cmdline lacks -vnc :%d (got %r)" % (label, disp, joined))
            require("-display" in argv and "none" in argv,
                    "%s: qemu cmdline lacks -display none" % label)
            require("-nic" in argv and "none" in argv,
                    "%s: qemu cmdline lacks -nic none" % label)
            require("-m" in argv and str(mem) in argv,
                    "%s: qemu cmdline lacks -m %d" % (label, mem))
        else:
            failures.append("%s: cannot read /proc/%d/cmdline" % (label, pid))

    # listener-table (netstat/ss) assertions
    ports = listen_ports()
    require(ports is not None, "%s: could not read LISTEN table" % label)
    if ports:
        require(vnc_port in ports, "%s: VNC port %d not in LISTEN table"
                % (label, vnc_port))
        require(web_port in ports, "%s: web port %d not in LISTEN table"
                % (label, web_port))

    # VNC protocol greeting (a real VNC server, not an arbitrary socket)
    greet = rfb_greeting(vnc_port)
    require(greet is not None, "%s: VNC port %d gave no RFB greeting"
            % (label, vnc_port))

    # web plane: static page
    page = http_get(web_port, "/")
    require(page is not None, "%s: web monitor %d unreachable" % (label, web_port))
    if page is not None:
        require(cfg["status_title"] in page, "%s: page missing status_title" % label)
        require(cfg["marker"] in page, "%s: page missing marker" % label)

    # live status endpoint
    body = http_get(web_port, "/cgi-bin/status.json")
    require(body is not None, "%s: /cgi-bin/status.json unreachable" % label)
    if body is not None:
        try:
            live = json.loads(body)
        except Exception as e:
            live = None
            failures.append("%s: status.json not valid JSON: %r" % (label, e))
        if live is not None:
            require(live.get("qemu_pid") == pid,
                    "%s: status qemu_pid %r != pidfile %r" % (label, live.get("qemu_pid"), pid))
            require(live.get("alive") == 1, "%s: status alive != 1" % label)
            require(live.get("vnc_port") == vnc_port,
                    "%s: status vnc_port %r != %d" % (label, live.get("vnc_port"), vnc_port))
            require(live.get("vnc_display") == disp,
                    "%s: status vnc_display mismatch" % label)
            require(live.get("web_port") == web_port,
                    "%s: status web_port mismatch" % label)
            require(live.get("marker") == cfg["marker"], "%s: status marker mismatch" % label)
            require(live.get("status_title") == cfg["status_title"],
                    "%s: status status_title mismatch" % label)
            require(live.get("mem_mib") == mem, "%s: status mem_mib mismatch" % label)
    print("%s: ok vnc=%s web=%s marker=%s" % (label, vnc_port, web_port, cfg["marker"]))
    teardown(cfg)
    time.sleep(0.4)

print("- default scenario")
if os.path.exists("/app/kiosk.conf"):
    run_scenario("default", "/app/kiosk.conf")
else:
    failures.append("no /app/kiosk.conf")

hidden = sorted(os.path.join(HALL, f) for f in os.listdir(HALL) if f.endswith(".json"))
for hp in hidden:
    if deadline_hit():
        failures.append("verifier deadline reached before running %s"
                        % os.path.basename(hp))
        break
    print("- hidden %s" % os.path.basename(hp))
    run_scenario(os.path.basename(hp), hp)
if len(hidden) < 2:
    failures.append("expected >=2 hidden scenarios, found %d" % len(hidden))

if failures:
    print("FAILURES:")
    for msg in failures:
        print("  - " + msg)
    open("/logs/verifier/reward.txt", "w").write("0")
else:
    print("ALL PASS (%d scenarios incl. hidden)" % (1 + len(hidden)))
    open("/logs/verifier/reward.txt", "w").write("1")
PYEOF
exit 0
