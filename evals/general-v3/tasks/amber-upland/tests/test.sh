#!/bin/bash
# Verifier for tasks/amber-upland (executes-deliverable).
#
# Independently:
#   * validates /app/initramfs.gz against the descriptor manifest (gzipped newc
#     cpio holding busybox, applet symlinks, exact char device nodes, the
#     directory_roots, and an executable /init that runs the manifest's mount
#     steps, prints the banner, and execs /bin/sh);
#   * executes /app/boot.sh for the default config and for each hidden config,
#     then checks the background qemu stays alive, the VNC TCP port for the
#     display, the web HTTP port (status title served), and a real interactive
#     busybox shell answering `echo <marker>` over the serial unix socket.
#
# Robustness (crash-proof): a numeric reward is ALWAYS written, even if this
# script is interrupted (harness timeout, signal) or the python body crashes.
# An internal deadline gates every blocking wait so a slow/hanging deliverable
# records 0 well before the harness verifier window (`verifier.timeout_sec`)
# instead of being killed silently. Output is unbuffered for forensics.
set -u
mkdir -p /logs/verifier

# If we exit for any reason without having written a reward, record 0.
__vfinal() { [ -f /logs/verifier/reward.txt ] || echo 0 > /logs/verifier/reward.txt; }
trap __vfinal EXIT
trap '__vfinal; exit 143' TERM INT

python3 -u - <<'PYEOF'
import json, os, shutil, signal, socket, stat, subprocess, sys, tempfile, time, urllib.request

failures = []
HALL = "/tests/hidden"
MAN = "/app/files/initramfs_manifest.json"

# Internal deadline: keep the whole verification comfortably inside the
# harness's verifier window even when a deliverable is slow or hangs. Every
# blocking wait is gated on this.
DEADLINE = time.time() + 450.0

def remaining():
    return max(2.0, DEADLINE - time.time())

def deadline_hit():
    return time.time() >= DEADLINE

def require(cond, msg):
    if not cond:
        failures.append(msg)

def run_boot(cfg_path):
    # Never wait past the deadline inside a single boot attempt.
    timeout = min(150.0, remaining())
    try:
        return subprocess.run(["bash", "/app/boot.sh", cfg_path],
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
    try:
        c = json.load(open(cfg))
    except Exception:
        return
    for key in ("pidfile", "web_pidfile"):
        if c.get(key):
            kill_pidfile(c[key])
    if c.get("console_socket") and os.path.exists(c["console_socket"]):
        try:
            os.unlink(c["console_socket"])
        except Exception:
            pass

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

def web_ok(port, status_title, tries=3):
    for _ in range(tries):
        if deadline_hit():
            return False
        try:
            with urllib.request.urlopen("http://127.0.0.1:%d/" % port, timeout=1.5) as r:
                if status_title in r.read().decode("utf-8", "replace"):
                    return True
        except Exception:
            pass
        time.sleep(0.4)
    return False

def shell_echo_ok(console_sock, marker, tries=20):
    for _ in range(tries):
        if deadline_hit():
            return False
        s = None
        try:
            s = socket.socket(socket.AF_UNIX)
            s.settimeout(2.5)
            s.connect(console_sock)
            s.sendall(b"\n")
            time.sleep(0.2)
            s.sendall(("echo %s\n" % marker).encode())
            buf = b""
            end = time.time() + 4
            while time.time() < end:
                try:
                    d = s.recv(4096)
                except socket.timeout:
                    break
                if not d:
                    break
                buf += d
            if marker.encode() in buf:
                return True
        except Exception:
            pass
        finally:
            if s is not None:
                try:
                    s.close()
                except Exception:
                    pass
        time.sleep(0.5)
    return False

def pid_alive(pidfile):
    try:
        with open(pidfile) as fh:
            pid = int(fh.read().strip())
        os.kill(pid, 0)
        return True
    except Exception:
        return False

# ---------------------------------------------------------------------------
# 1) Deliverables present + executable
# ---------------------------------------------------------------------------
for p in ("/app/initramfs.gz", "/app/boot.sh", "/app/vnc.conf"):
    require(os.path.exists(p), "missing deliverable %s" % p)
require(os.access("/app/boot.sh", os.X_OK), "/app/boot.sh not executable")
if not os.path.exists("/app/boot.sh"):
    print("fatal: no /app/boot.sh")
    open("/logs/verifier/reward.txt", "w").write("0")
    sys.exit(0)

# ---------------------------------------------------------------------------
# 2) initramfs content vs the descriptor manifest
# ---------------------------------------------------------------------------
if os.path.exists("/app/initramfs.gz") and os.path.exists(MAN):
    m = json.load(open(MAN))
    vd = tempfile.mkdtemp(prefix="vk_")
    try:
        subprocess.run(
            ["bash", "-c",
             "cd '%s' && gzip -dc /app/initramfs.gz | cpio -id --quiet 2>/dev/null" % vd],
            check=False)
        raw = open("/app/initramfs.gz", "rb").read(2)
        require(raw == b"\x1f\x8b", "initramfs.gz is not gzipped (magic %r)" % raw)

        biny = os.path.join(vd, "bin", "busybox")
        require(os.path.isfile(biny), "/bin/busybox missing in initramfs")
        if os.path.isfile(biny):
            require(open(biny, "rb").read(4) == b"\x7fELF", "/bin/busybox not ELF")

        for link in m.get("applet_links", []):
            lp = os.path.join(vd, link.lstrip("/"))
            ok = os.path.islink(lp) and os.path.basename(os.readlink(lp)) == "busybox"
            require(ok, "applet %s must be a symlink to busybox" % link)

        for node in m.get("device_nodes", []):
            np_ = os.path.join(vd, node["path"].lstrip("/"))
            require(os.path.exists(np_), "device node missing: %s" % node["path"])
            if os.path.exists(np_):
                st = os.lstat(np_)
                require(stat.S_ISCHR(st.st_mode), "%s not a char device" % node["path"])
                want = (int(node["major"]), int(node["minor"]))
                got = (os.major(st.st_rdev), os.minor(st.st_rdev))
                require(got == want, "%s major/minor %d:%d != %d:%d"
                        % (node["path"], got[0], got[1], want[0], want[1]))

        for d in m.get("directory_roots", []):
            dp = os.path.join(vd, d.lstrip("/"))
            require(os.path.isdir(dp), "directory missing in initramfs: %s" % d)

        ip_ = os.path.join(vd, "init")
        require(os.path.exists(ip_), "/init missing in initramfs")
        if os.path.exists(ip_):
            require(os.access(ip_, os.X_OK), "/init not executable")
            content = open(ip_).read()
            require("#!/bin/sh" in content, "/init missing shebang")
            require(m["init"]["banner"] in content, "/init missing banner")
            for step in m.get("init", {}).get("mount_steps", []):
                require(step in content, "init must run mount step: %s" % step)
            require("exec %s" % m["init"]["exec_shell"] in content,
                    "/init does not exec its shell")
    finally:
        shutil.rmtree(vd, ignore_errors=True)
else:
    failures.append("cannot validate initramfs against manifest")

# ---------------------------------------------------------------------------
# 3) execute boot.sh for the default + each hidden scenario
# ---------------------------------------------------------------------------
def run_scenario(label, cfg_path):
    cfg = json.load(open(cfg_path))
    teardown(cfg_path)
    r = run_boot(cfg_path)
    if r is None:
        failures.append("%s: boot.sh timed out" % label)
        teardown(cfg_path)
        return
    if r.returncode != 0:
        failures.append("%s: boot.sh rc=%s stderr=%r"
                        % (label, r.returncode, (r.stderr or "")[-250:]))
        teardown(cfg_path)
        return

    vnc_tcp = 5900 + int(cfg["vnc_display"])
    web_port = int(cfg["web_port"])
    marker = cfg["marker"]
    title = cfg["status_title"]
    sock = cfg["console_socket"]
    pidf = cfg["pidfile"]

    ready = False
    for _ in range(40):
        if deadline_hit():
            break
        if (pid_alive(pidf) and tcp_open(vnc_tcp) and tcp_open(web_port)
                and os.path.exists(sock)):
            ready = True
            break
        time.sleep(1)
    if not ready:
        failures.append("%s: VM never became ready (vnc %d web %d)"
                        % (label, vnc_tcp, web_port))
        teardown(cfg_path)
        return

    require(pid_alive(pidf), "%s: background qemu pid not alive" % label)
    require(tcp_open(vnc_tcp, tries=3), "%s: VNC listener not open on %d"
            % (label, vnc_tcp))
    require(web_ok(web_port, title, tries=3), "%s: web monitor %d missing title %r"
            % (label, web_port, title))
    require(shell_echo_ok(sock, marker), "%s: no interactive shell answered marker %r"
            % (label, marker))
    print("%s: ok vnc=%s web=%s marker=%s" % (label, vnc_tcp, web_port, marker))
    teardown(cfg_path)
    time.sleep(0.4)

print("- default scenario")
if os.path.exists("/app/vnc.conf"):
    run_scenario("default", "/app/vnc.conf")
else:
    failures.append("no /app/vnc.conf")

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