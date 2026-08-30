#!/usr/bin/env bash
# drift-summit verifier. Runs as root after the agent finishes, in the same
# container, with /tests mounted read-only at /tests.
set -u
mkdir -p /logs/verifier
R=1
LOG=/tmp/verify.log
: > "$LOG"
log() { echo "$*" | tee -a "$LOG"; }
fail() { log "FAIL: $*"; R=0; }
pass() { log "PASS: $*"; }

# ---------------------------------------------------------------------------
# Independent reference implementations (documented task spec, not oracle code)
# ---------------------------------------------------------------------------
cat > /tmp/ref_events.py <<'PY'
import json, sys
MARKERS = ["error", "fault", "timeout"]
FIELDS = ("message", "status")
def markers(rec):
    found = []
    for m in MARKERS:
        for f in FIELDS:
            if m in str(rec.get(f, "")).lower():
                found.append(m)
                break
    return sorted(found)
recs = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
kept, occ = [], 0
for r in recs:
    ms = markers(r)
    if ms:
        kept.append(dict(r, _markers=ms)); occ += len(ms)
print("total=%d" % len(recs))
print("error_marked=%d" % len(kept))
print("marker_occurrences=%d" % occ)
print("---preserved---")
for r in kept:
    print(json.dumps(r))
print("---end---")
PY

cat > /tmp/ref_smp.py <<'PY'
import sys
OPS = {"PUSH":1,"LOAD":1,"STORE":1,"JMP":1,"JZ":1,"JNZ":1,
       "POP":0,"ADD":0,"SUB":0,"MUL":0,"DIV":0,"DUP":0,"SWAP":0,"OUT":0,"HALT":0}
prog, order = {}, []
for ln in open(sys.argv[1]):
    s = ln.strip()
    if not s or s.startswith("#"):
        continue
    tok = s.split()
    a = int(tok[0], 16); op = tok[1].upper()
    oper = None
    if OPS[op] == 1:
        if op == "PUSH":
            oper = int(tok[2], 10)
        elif op in ("LOAD", "STORE"):
            oper = int(tok[2], 10)
        else:
            oper = int(tok[2], 16)
    prog[a] = [op, oper]; order.append(a)
pc = order[0]; stack = []; regs = [0]*8; halted = False
def step():
    global pc, halted
    a = pc; op, oper = prog[a]
    if op == "PUSH": stack.append(oper)
    elif op == "LOAD": stack.append(regs[oper])
    elif op == "STORE": regs[oper] = stack.pop()
    elif op == "POP": stack.pop()
    elif op in ("ADD","SUB","MUL","DIV"):
        b, x = stack.pop(), stack.pop()
        stack.append({"ADD": x+b, "SUB": x-b, "MUL": x*b, "DIV": x//b}[op])
    elif op == "DUP": stack.append(stack[-1])
    elif op == "SWAP": stack[-1], stack[-2] = stack[-2], stack[-1]
    elif op == "OUT": stack.pop()
    elif op in ("JMP","JZ","JNZ"):
        v = None
        if op != "JMP":
            v = stack.pop()
        if op == "JMP" or (op == "JZ" and v == 0) or (op == "JNZ" and v != 0):
            pc = oper
        else:
            pc = order[order.index(a) + 1]
    elif op == "HALT":
        halted = True
        pc = a
    if not halted and pc == a:
        nxt = order.index(a) + 1
        pc = order[nxt] if nxt < len(order) else order[-1] + 1
    print("exec 0x%04x" % a)
while not halted:
    step()
PY

cat > /tmp/cmp_events.py <<'PY'
import json, sys
def parse(path):
    counts = {}
    preserved = []
    section = False
    for ln in open(path):
        s = ln.strip()
        if s.startswith("total="):
            counts["total"] = int(s.split("=", 1)[1])
        elif s.startswith("error_marked="):
            counts["error_marked"] = int(s.split("=", 1)[1])
        elif s.startswith("marker_occurrences="):
            counts["marker_occurrences"] = int(s.split("=", 1)[1])
        elif s == "---preserved---":
            section = True
        elif s == "---end---":
            section = False
        elif section and s:
            preserved.append(json.loads(s))
    return counts, preserved
a_cnt, a_pres = parse(sys.argv[1])
b_cnt, b_pres = parse(sys.argv[2])
if a_cnt != b_cnt:
    print("COUNTS-DIFF %r vs %r" % (a_cnt, b_cnt)); sys.exit(1)
if a_pres != b_pres:
    print("PRESERVED-DIFF n=%d vs n=%d" % (len(a_pres), len(b_pres))); sys.exit(1)
print("OK")
PY

# ---------------------------------------------------------------------------
# Deliverable presence
# ---------------------------------------------------------------------------
for f in /app/session.log /app/daemons.pid /app/debug.txt /app/sudo.txt \
         /app/analyze_events.py /app/step_trace.py /app/monitor.py; do
    [ -f "$f" ] && pass "artifact present: $f" || fail "missing artifact: $f"
done

# ---------------------------------------------------------------------------
# 1. Daemons: sshd:2222 + http:8080 alive, matching /app/daemons.pid
# ---------------------------------------------------------------------------
if [ -f /app/daemons.pid ]; then
    SSHDPID=$(awk '$1=="sshd"{print $2}' /app/daemons.pid)
    HTTPDPID=$(awk '$1=="httpd"{print $2}' /app/daemons.pid)
    NLINES=$(awk 'NF==2{print $1}' /app/daemons.pid | grep -cE '^(sshd|httpd)$')
    [ "$NLINES" = "2" ] && pass "daemons.pid has 2 lines" || fail "daemons.pid malformed ($NLINES lines)"
    if echo "$SSHDPID" | grep -qE '^[0-9]+$'; then
        if [ -r "/proc/$SSHDPID/comm" ] && [ "$(cat /proc/$SSHDPID/comm)" = "sshd" ]; then
            pass "sshd pid $SSHDPID is an sshd process"
        else
            fail "sshd pid $SSHDPID is not an sshd process"
        fi
    else
        fail "sshd pid not an integer: '$SSHDPID'"
    fi
    if echo "$HTTPDPID" | grep -qE '^[0-9]+$'; then
        if [ -r "/proc/$HTTPDPID/cmdline" ] && tr '\0' ' ' < "/proc/$HTTPDPID/cmdline" | grep -q 'http.server 8080'; then
            pass "httpd pid $HTTPDPID is an http.server process"
        else
            fail "httpd pid $HTTPDPID is not an http.server process"
        fi
    else
        fail "httpd pid not an integer: '$HTTPDPID'"
    fi
    if timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/2222' 2>/dev/null; then
        pass "port 2222 (sshd) accepts connections"
    else
        fail "port 2222 (sshd) closed"
    fi
    if curl -s --max-time 5 http://127.0.0.1:8080/ 2>/dev/null | grep -q 'plume-ridge-7'; then
        pass "port 8080 (httpd) serves the site"
    else
        fail "port 8080 (httpd) did not serve the site"
    fi
else
    fail "no /app/daemons.pid to check"
fi

# ---------------------------------------------------------------------------
# 2. tmux pane + long-running monitor
# ---------------------------------------------------------------------------
if command -v tmux >/dev/null 2>&1 && tmux has-session -t ops-session 2>/dev/null; then
    pass "tmux session ops-session exists"
    PANEPID=$(tmux list-panes -t ops-session -F '#{pane_pid}' 2>/dev/null | head -1)
    if echo "$PANEPID" | grep -qE '^[0-9]+$'; then
        if [ -r "/proc/$PANEPID/cmdline" ] && tr '\0' ' ' < "/proc/$PANEPID/cmdline" | grep -q 'monitor.py'; then
            pass "pane $PANEPID runs the monitor script"
        else
            fail "pane process not running monitor.py"
        fi
    else
        fail "could not resolve pane pid"
    fi
else
    fail "tmux session ops-session missing"
fi
if [ -f /srv/monitor/tally.out ]; then
    if grep -qE '^[0-9]+ [0-9]+\.[0-9]+ alive$' /srv/monitor/tally.out; then
        pass "tally.out lines match monitor format"
    else
        fail "tally.out lines malformed"
    fi
    S1=$(stat -c %s /srv/monitor/tally.out)
    sleep 2.2
    S2=$(stat -c %s /srv/monitor/tally.out)
    if [ "$S2" -gt "$S1" ]; then
        pass "tally.out keeps growing ($S1 -> $S2)"
    else
        fail "tally.out not growing ($S1 -> $S2)"
    fi
else
    fail "no /srv/monitor/tally.out"
fi

# ---------------------------------------------------------------------------
# 3. Debugger trace: visible fib + /app/debug.txt
# ---------------------------------------------------------------------------
if [ -x /app/step_trace.py ] || python3 -c "import ast;ast.parse(open('/app/step_trace.py').read())" 2>/dev/null; then
    python3 /tmp/ref_smp.py /srv/programs/fib.smp > /tmp/ref_fib.txt
    python3 /app/step_trace.py /srv/programs/fib.smp 16 > /tmp/run_fib.txt 2>&1
    if grep -q 'program /srv/programs/fib.smp loaded:' /tmp/run_fib.txt; then
        pass "fib run reports program load"
    else
        fail "fib run missing program load line"
    fi
    if [ "$(grep -c '^exec ' /tmp/run_fib.txt)" = "16" ] && [ "$(wc -l < /tmp/ref_fib.txt)" -ge 16 ]; then
        grep '^exec ' /tmp/run_fib.txt | head -n 16 > /tmp/exec_fib.txt
        head -n 16 /tmp/ref_fib.txt > /tmp/exp_fib16.txt
        if diff -q /tmp/exec_fib.txt /tmp/exp_fib16.txt >/dev/null; then
            pass "fib 16-step executed-address sequence matches independent trace"
        else
            fail "fib executed-address sequence diverges from independent trace"
            log "--- driver trace ---"; head -5 /tmp/exec_fib.txt
            log "--- expected ---"; head -5 /tmp/exp_fib16.txt
        fi
    else
        fail "fib run produced wrong exec count (driver=$(grep -c '^exec ' /tmp/run_fib.txt), ref=$(wc -l < /tmp/ref_fib.txt))"
    fi
    if grep -q '^stopped ' /tmp/run_fib.txt && ! grep -q '^halt ' /tmp/run_fib.txt; then
        pass "fib 16-step trace ends without halting"
    else
        fail "fib trace lacks a stopped line before regs"
    fi
    # deliverable /app/debug.txt must be a real trace of the visible program
    if [ -f /app/debug.txt ]; then
        if grep -q 'program /srv/programs/fib.smp loaded:' /app/debug.txt; then
            pass "debug.txt ran the visible fib program"
        else
            fail "debug.txt did not load fib.smp"
        fi
        grep '^exec ' /app/debug.txt | head -n 16 > /tmp/exec_dbg.txt
        if diff -q /tmp/exec_dbg.txt /tmp/exp_fib16.txt >/dev/null; then
            pass "debug.txt executed-address prefix matches independent trace"
        else
            fail "debug.txt executed-address prefix diverges"
        fi
    else
        fail "no /app/debug.txt"
    fi
else
    fail "no usable /app/step_trace.py"
fi

# ---------------------------------------------------------------------------
# 4. Marker detection: visible + hidden event streams
# ---------------------------------------------------------------------------
if [ -f /app/analyze_events.py ]; then
    for ev in current events-e2 events-e3; do
        case "$ev" in
            current) SRC=/srv/events/current.ndjson ;;
            *) SRC=/tests/hidden/$ev.ndjson ;;
        esac
        python3 /app/analyze_events.py "$SRC" > /tmp/agent_ev.txt 2>&1 || { fail "analyzer on $ev exited nonzero"; continue; }
        python3 /tmp/ref_events.py "$SRC" > /tmp/ref_ev.txt
        if [ "$ev" = "current" ]; then cp /tmp/ref_ev.txt /tmp/ref_vis.txt; fi
        if python3 /tmp/cmp_events.py /tmp/agent_ev.txt /tmp/ref_ev.txt > /tmp/cmp_ev.txt; then
            pass "analyzer matches reference on $ev"
        else
            fail "analyzer diverges from reference on $ev: $(cat /tmp/cmp_ev.txt)"
        fi
    done
    # visible report embedded in /app/session.log must match the reference
    if [ -f /app/session.log ]; then
        awk '/^=== marker report ===$/{f=1;next} /^=== end marker report ===$/{f=0} f' /app/session.log > /tmp/sl_rep.txt
        if [ -s /tmp/sl_rep.txt ]; then
            if python3 /tmp/cmp_events.py /tmp/sl_rep.txt /tmp/ref_vis.txt > /tmp/cmp_ev2.txt; then
                pass "session.log marker report matches reference"
            else
                fail "session.log marker report diverges: $(cat /tmp/cmp_ev2.txt)"
            fi
        else
            fail "session.log contains no marker report section"
        fi
    fi
else
    fail "no /app/analyze_events.py"
fi

# ---------------------------------------------------------------------------
# 5. Sudo enumeration: grants == sudoers config; summary content via sudo
# ---------------------------------------------------------------------------
if [ -f /app/sudo.txt ]; then
    EXPECTED=$(python3 - <<'PY'
import re
cfg = open("/etc/sudoers.d/ops").read()
part = re.split(r"NOPASSWD:", cfg)[1]
cmds = sorted(c.strip() for c in part.split(",") if c.strip())
for c in cmds:
    print(c)
PY
)
    GOT=$(sed -n 's/^allowed-cmd: //p' /app/sudo.txt | sort)
    if [ "$GOT" = "$EXPECTED" ]; then
        pass "sudo.txt enumerates exactly the granted commands"
    else
        fail "sudo.txt command list $(echo "$GOT" | tr '\n' ';') != configured $(echo "$EXPECTED" | tr '\n' ';')"
    fi
    if grep -q '^summary: ' /app/sudo.txt; then
        GOTSUM=$(sed -n 's/^summary: //p' /app/sudo.txt)
        EXPSUM=$(cat /srv/restricted/summary.txt)
        if [ "$GOTSUM" = "$EXPSUM" ]; then
            pass "sudo.txt summary equals restricted file content"
        else
            fail "sudo.txt summary differs from restricted file"
        fi
    else
        fail "sudo.txt missing summary line"
    fi
else
    fail "no /app/sudo.txt"
fi

# ---------------------------------------------------------------------------
# 6. session.log journal integrity
# ---------------------------------------------------------------------------
if [ -f /app/session.log ]; then
    [ "$(sed -n 's/^host=//p' /app/session.log | head -1)" = "$(hostname)" ] \
        && pass "session.log host matches" || fail "session.log host mismatch"
    grep -q '^tmux-session=ops-session$' /app/session.log && pass "session.log tmux-session line" || fail "session.log tmux-session missing"
    grep -q '^tmux-pane=0.0$' /app/session.log && pass "session.log tmux-pane line" || fail "session.log tmux-pane missing"
    if [ -f /app/daemons.pid ]; then
        SSP=$(awk '$1=="sshd"{print $2}' /app/daemons.pid)
        HSP=$(awk '$1=="httpd"{print $2}' /app/daemons.pid)
        [ "$(sed -n 's/^sshd_pid=//p' /app/session.log | head -1)" = "$SSP" ] \
            && pass "session.log sshd_pid matches daemons.pid" || fail "session.log sshd_pid mismatch"
        [ "$(sed -n 's/^httpd_pid=//p' /app/session.log | head -1)" = "$HSP" ] \
            && pass "session.log httpd_pid matches daemons.pid" || fail "session.log httpd_pid mismatch"
    fi
else
    fail "no /app/session.log"
fi

# ---------------------------------------------------------------------------
# Hidden generalization: driver on different SMP programs
# ---------------------------------------------------------------------------
if [ -f /app/step_trace.py ]; then
    python3 /tmp/ref_smp.py /tests/hidden/prog-mul.smp > /tmp/ref_mul.txt
    python3 /app/step_trace.py /tests/hidden/prog-mul.smp 7 > /tmp/run_mul.txt 2>&1
    if grep -q 'program /tests/hidden/prog-mul.smp loaded:' /tmp/run_mul.txt; then
        pass "mul run loaded the hidden program"
    else
        fail "mul run did not load prog-mul.smp"
    fi
    if [ "$(grep -c '^exec ' /tmp/run_mul.txt)" = "7" ]; then
        grep '^exec ' /tmp/run_mul.txt > /tmp/exec_mul.txt
        head -n 7 /tmp/ref_mul.txt > /tmp/exp_mul7.txt
        if diff -q /tmp/exec_mul.txt /tmp/exp_mul7.txt >/dev/null; then
            pass "mul 7-step trace matches independent trace"
        else
            fail "mul trace diverges from independent trace"
            log "--- got ---"; cat /tmp/exec_mul.txt
            log "--- expected ---"; cat /tmp/exp_mul7.txt
        fi
    else
        fail "mul run produced wrong exec count ($(grep -c '^exec ' /tmp/run_mul.txt))"
    fi
    if grep -q '^stopped ' /tmp/run_mul.txt && ! grep -q '^halt ' /tmp/run_mul.txt; then
        pass "mul stops before halt"
    else
        fail "mul trace did not stop before halt: $(grep -E '^(halt|stopped) ' /tmp/run_mul.txt)"
    fi

    python3 /tmp/ref_smp.py /tests/hidden/prog-fact.smp > /tmp/ref_fact.txt
    python3 /app/step_trace.py /tests/hidden/prog-fact.smp 80 > /tmp/run_fact.txt 2>&1
    if grep -q 'program /tests/hidden/prog-fact.smp loaded:' /tmp/run_fact.txt; then
        pass "fact run loaded the hidden program"
    else
        fail "fact run did not load prog-fact.smp"
    fi
    if [ "$(grep -c '^exec ' /tmp/run_fact.txt)" = "$(wc -l < /tmp/ref_fact.txt)" ]; then
        grep '^exec ' /tmp/run_fact.txt > /tmp/exec_fact.txt
        if diff -q /tmp/exec_fact.txt /tmp/ref_fact.txt >/dev/null; then
            pass "fact full trace matches independent trace"
        else
            fail "fact full trace diverges"
        fi
    else
        fail "fact run exec count $(grep -c '^exec ' /tmp/run_fact.txt) != full run $(wc -l < /tmp/ref_fact.txt)"
    fi
    if grep -q '^halt ' /tmp/run_fact.txt && ! grep -q '^stopped ' /tmp/run_fact.txt; then
        pass "fact halts at the end"
    else
        fail "fact trace did not halt: $(grep -E '^(halt|stopped) ' /tmp/run_fact.txt)"
    fi
fi

echo "$R" > /logs/verifier/reward.txt
log "REWARD=$R"
exit 0