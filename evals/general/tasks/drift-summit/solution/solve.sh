#!/usr/bin/env bash
# drift-summit oracle: performs the real session-operator work and produces
# every deliverable in /app. Never reads /tests.
set -euo pipefail
export TERM=xterm

# ---------------------------------------------------------------------------
# 1) Long-lived daemons: sshd (2222) + HTTP file server (8080), detached so
#    they survive this script's exit.
# ---------------------------------------------------------------------------
mkdir -p /run/sshd
if ! pgrep -x sshd >/dev/null 2>&1; then
    setsid /usr/sbin/sshd -D -p 2222 </dev/null >/var/log/sshd-drift.log 2>&1 &
fi
if ! pgrep -f 'http.server 8080' >/dev/null 2>&1; then
    setsid python3 -m http.server 8080 --bind 0.0.0.0 --directory /srv/site \
        </dev/null >/var/log/httpd-drift.log 2>&1 &
fi
sleep 1.2
SSHDPID=$(pgrep -x sshd 2>/dev/null | tail -1)
HTTPDPID=$(pgrep -f 'http.server 8080' 2>/dev/null | tail -1)
printf 'sshd %s\nhttpd %s\n' "$SSHDPID" "$HTTPDPID" > /app/daemons.pid

# ---------------------------------------------------------------------------
# 2) Long-running monitor governed inside a specific tmux pane (ops-session:0.0)
# ---------------------------------------------------------------------------
cat > /app/monitor.py <<'PY'
#!/usr/bin/env python3
import time
OUT = "/srv/monitor/tally.out"
i = 0
while True:
    with open(OUT, "a") as fh:
        fh.write("%d %.6f alive\n" % (i, time.time()))
    i += 1
    time.sleep(2)
PY
chmod +x /app/monitor.py
if ! tmux has-session -t ops-session 2>/dev/null; then
    tmux new-session -d -s ops-session -x 200 -y 50
    sleep 0.4
fi
tmux send-keys -t ops-session:0.0 "exec python3 /app/monitor.py" Enter
sleep 0.6

# ---------------------------------------------------------------------------
# 3) Interactive instruction-level debugger driven by line commands on stdin.
#    step_trace.py pipes a command sequence into /opt/smp/smp_debug.py.
# ---------------------------------------------------------------------------
cat > /app/step_trace.py <<'PY'
#!/usr/bin/env python3
"""Drive the SMP debugger with a piped sequence of line commands on stdin.

usage: step_trace.py [program] [steps]
defaults: /srv/programs/fib.smp, 16 steps
Prints the debugger's transcript to stdout.
"""
import subprocess
import sys

DEBUGGER = "/opt/smp/smp_debug.py"


def main():
    prog = sys.argv[1] if len(sys.argv) > 1 else "/srv/programs/fib.smp"
    steps = int(sys.argv[2]) if len(sys.argv) > 2 else 16
    cmds = [
        "load %s" % prog,
        "regs",
        "trace %d" % steps,
        "regs",
        "quit",
    ]
    p = subprocess.run([sys.executable, DEBUGGER],
                       input="\n".join(cmds) + "\n",
                       capture_output=True, text=True)
    sys.stdout.write(p.stdout)
    sys.stderr.write(p.stderr)
    return p.returncode


if __name__ == "__main__":
    raise SystemExit(main())
PY
chmod +x /app/step_trace.py
python3 /app/step_trace.py > /app/debug.txt

# ---------------------------------------------------------------------------
# 4) Marker-message detection over the event stream (reusable analyzer).
# ---------------------------------------------------------------------------
cat > /app/analyze_events.py <<'PY'
#!/usr/bin/env python3
"""Event-stream analyzer: detect error-marker records and report them.

A record is error-marked when any of the case-insensitive marker substrings
("error", "fault", "timeout") occurs in its `message` or `status` field.
Marked records are preserved (input order) and annotated with _markers.
Prints a report to stdout: total / error_marked / marker_occurrences counts,
then the preserved records between ---preserved--- and ---end---.

usage: analyze_events.py <path>   (or read stdin with path "-")
"""
import json
import sys

MARKERS = ["error", "fault", "timeout"]
FIELDS = ("message", "status")


def record_markers(rec):
    found = []
    for m in MARKERS:
        for f in FIELDS:
            if m in str(rec.get(f, "")).lower():
                found.append(m)
                break
    return sorted(found)


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "/dev/stdin"
    if path == "-":
        path = "/dev/stdin"
    records = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if line:
                records.append(json.loads(line))
    kept, occ = [], 0
    for rec in records:
        ms = record_markers(rec)
        if ms:
            kept.append(dict(rec, _markers=ms))
            occ += len(ms)
    print("total=%d" % len(records))
    print("error_marked=%d" % len(kept))
    print("marker_occurrences=%d" % occ)
    print("---preserved---")
    for rec in kept:
        print(json.dumps(rec))
    print("---end---")


if __name__ == "__main__":
    main()
PY
chmod +x /app/analyze_events.py
python3 /app/analyze_events.py /srv/events/current.ndjson > /tmp/rep.txt

# ---------------------------------------------------------------------------
# 5) Enumerate sudo grants for session user ops, then use the permitted
#    elevated command to read the root-only restricted file.
# ---------------------------------------------------------------------------
python3 - <<'PY'
import re
import subprocess

out = subprocess.run(["sudo", "-n", "-l", "-U", "ops"],
                     capture_output=True, text=True, check=True).stdout
# Normalize sudo -l output: command entries live after each "NOPASSWD:" and
# may wrap across lines. Join continuation whitespace, then split on commas.
blocks = re.split(r"NOPASSWD:", out)
cmds = []
for b in blocks[1:]:
    joined = re.sub(r"\s+", " ", b).strip()
    for piece in joined.split(","):
        piece = piece.strip()
        if piece and not piece.startswith("("):
            cmds.append(piece)
cmds = sorted(set(cmds))
summary = subprocess.run(
    ["runuser", "-u", "ops", "--", "sudo", "-n", "/usr/bin/head",
     "-c", "4096", "/srv/restricted/summary.txt"],
    capture_output=True, text=True, check=True).stdout.rstrip("\n")
with open("/app/sudo.txt", "w") as fh:
    for c in cmds:
        fh.write("allowed-cmd: %s\n" % c)
    fh.write("summary: %s\n" % summary)
PY

# ---------------------------------------------------------------------------
# 6) Session journal tying the session state together.
# ---------------------------------------------------------------------------
{
    echo "session-log v1"
    echo "host=$(hostname)"
    echo "tmux-session=ops-session"
    echo "tmux-pane=0.0"
    echo "sshd_pid=$SSHDPID"
    echo "httpd_pid=$HTTPDPID"
    echo "=== marker report ==="
    cat /tmp/rep.txt
    echo "=== end marker report ==="
} > /app/session.log

echo "oracle deliverable inventory:"
ls -la /app
cat /app/daemons.pid