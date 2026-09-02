#!/bin/bash
# prism-anchor verifier.
# Executes the /app/configure.sh and /app/fixperms.sh deliverables (visible
# shared area plus hidden variant/edge/malformed scenarios), re-runs the
# /app/mapper.py normalize() deliverable on visible + hidden example sets, and
# validates the /app/dump.txt evidence bundle (recovered deleted server source
# & secret, targeted-suite pass count, cProfile stats, verbatim terminal tail).
# Always writes a numeric reward to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0

SHARE=/srv/prism
GROUP=anchorline
MEMBER=meridian
OUTSIDER=hopper
PASS=1
fail(){ echo "  FAIL: $1" >&2; PASS=0; }
need(){ [ -e "$1" ] || fail "missing deliverable $1"; }

# --------------------------------------------------------------- presence
for f in /app/configure.sh /app/fixperms.sh /app/mapper.py /app/dump.txt; do
  need "$f"
done
[ -x /app/configure.sh ] || fail "configure.sh not executable"
[ -x /app/fixperms.sh ] || fail "fixperms.sh not executable"

# ------------------------------------------------------- visible configure.sh
if bash /app/configure.sh; then
  # C1 non-members denied list/read/create
  runuser -u "$OUTSIDER" -- bash -c "cd $SHARE" 2>/dev/null && fail "outsider can cd into share"
  runuser -u "$OUTSIDER" -- bash -c "grep -q level '$SHARE/data/relay.dat'" 2>/dev/null && fail "outsider read share data"
  runuser -u "$OUTSIDER" -- bash -c "dd if=/dev/null of=$SHARE/data/leak.tmp" 2>/dev/null && fail "outsider created file"
  [ -e "$SHARE/data/leak.tmp" ] && fail "outsider-created file exists"
  case "$(stat -c %a "$SHARE")" in 0770|770) : ;; *) fail "share mode $(stat -c %a "$SHARE") not groups-only";; esac

  # C4 ACL mask preserves group execute in bin
  getfacl -c "$SHARE/bin" | grep -q 'default:mask::rwx' || fail "ACL default mask lost execute"
  getfacl -c "$SHARE/bin" | grep -q "default:group:$GROUP:rwx" || fail "ACL default group lacks rwx"
  getfacl -c "$SHARE/bin" | grep -qE '^mask::rwx' || fail "ACL effective mask lost execute"
  grep -q '^PasswordAuthentication yes' /etc/ssh/sshd_config || fail "PasswordAuthentication not enabled"
  [ -e "$SHARE/.relay.pid" ] || [ -e "$SHARE/relay.bak" ] && fail "stale lifecycle file remains"
  bash /app/configure.sh || fail "configure.sh not idempotent"
else
  fail "configure.sh returned nonzero"
fi

# ---------------------------------------------------------- visible fixperms.sh
bash /app/fixperms.sh "$SHARE/bin" || fail "fixperms.sh nonzero"
[ -x "$SHARE/bin/heartbeat.sh" ] || fail "heartbeat.sh not executable"
[ -x "$SHARE/bin/tide.sh" ] || fail "tide.sh not executable"
head -n1 "$SHARE/bin/tide.sh" >/dev/null 2>&1 || fail "tide.sh not readable"
[ "$(runuser -u "$MEMBER" -- "$SHARE/bin/heartbeat.sh" 2>/dev/null || true)" = "heartbeat-ok" ] || fail "member 'heartbeat' exec failed"
[ "$(runuser -u "$MEMBER" -- "$SHARE/bin/tide.sh" 2>/dev/null || true)" = "tide-ok" ] || fail "member 'tide' exec failed"
runuser -u "$OUTSIDER" -- bash -c "$SHARE/bin/heartbeat.sh" 2>/dev/null && fail "outsider executed script in share"

# ------------------------------------------------------ dump.txt evidence bundle
echo "--- dumping check"
python3 - <<'PY'
import os, re, subprocess, sys

ok = True
def ck(cond, msg):
    global ok
    if not cond:
        ok = False
        print("  FAIL:", msg)

dump = open("/app/dump.txt").read()

def section(name):
    m = re.search(r"^====\[%s\]====\s*\n(.*?)(?=^====\[[A-Z0-9_]+\]====|\Z)" % re.escape(name),
                  dump, re.S | re.M)
    return (m.group(1).strip("\n") if m else "")

# 1) recovered server source + secret (locate source of deleted-but-open script)
pid = None
for x in subprocess.run("pgrep -x python3", shell=True, capture_output=True, text=True).stdout.split():
    try:
        args = open("/proc/%s/cmdline" % x, "rb").read().decode(errors="replace").replace("\0", " ")
    except OSError:
        continue
    if "prism-north/telemetry.py" in args:
        pid = x
        break
ck(pid is not None, "could not locate telemetry process")
fd = None
for d in os.listdir("/proc/%s/fd" % pid):
    try:
        t = os.readlink("/proc/%s/fd/%s" % (pid, d))
    except OSError:
        continue
    if "deleted" in t:
        fd = d; break
ck(fd is not None, "could not locate deleted fd from running process")
truth = open("/proc/%s/fd/%s" % (pid, fd)).read()
secret = re.search(r'^SECRET = "([^"]+)"', truth, re.M).group(1)
serv = section("SERVER_RECOVERY")
ck(secret and secret in serv, "recovered source not in dump.txt")
ck('_SOURCE = open(__file__' in serv, "recovered source missing the held fd line")
ck('stamp' in serv, "recovered source missing function body")
ck(section("SECRET").strip() == secret, "dump SECRET != recovered secret")

# 2) transform verified against example set (visible)
real = subprocess.run(["python3", "/app/mapper.py", "/app/examples.json"],
                      capture_output=True, text=True).stdout.splitlines()
ck(section("TRANSFORM").strip() == real[0].strip(), "dump TRANSFORM != mapper visible output")
ck(section("TRANSFORM_OK").strip() == real[-1].strip(), "TRANSFORM_OK wrong")

# 3) targeted-suite pass count in dump matches an independent rerun
actual = subprocess.run("python3 -m pytest -q /app/qa/suite", shell=True,
                        capture_output=True, text=True)
actual = (actual.stdout or "") + (actual.stderr or "")
tail_count = re.search(r'([0-9]+) passed', actual)
ck(tail_count is not None, "suite produced no pass summary")
truth_count = tail_count.group(1)
st = section("SUITE_TAIL")
ck(re.search(r'\b%s passed\b' % truth_count, st), "dump SUITE_TAIL wrong count (%r)" % st)

# 4) cProfile stats present
ck("spin_tally" in section("PROFILE_TOP"), "dump PROFILE_TOP missing spin_tally")

# 5) terminal ending text captured verbatim
tty = subprocess.run("tail -n1 /tmp/prism-north/boot.log", shell=True,
                     capture_output=True, text=True).stdout.strip()
ck(section("TERMINAL_TAIL").strip() == tty, "dump TERMINAL_TAIL != boot tail (%r)" % tty)

sys.exit(0 if ok else 1)
PY
[ $? -eq 0 ] || fail "dump.txt evidence checks failed"

# ---------------------------------------------------------------- hidden cases
for i in 1 2 3; do
  case_dir="/tests/hidden/case$i"
  [ -f "$case_dir/input/scenario.json" ] || continue
  if python3 /tests/hidden/checker.py "$case_dir"; then
    :
  else
    fail "hidden case$i failed"
  fi
done

[ "$PASS" = 1 ] && reward=1
echo "$reward" > /logs/verifier/reward.txt
exit 0