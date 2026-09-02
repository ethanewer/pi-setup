#!/usr/bin/env bash
# echo-mantle verifier. Writes the numeric reward to /logs/verifier/reward.txt
# Runs as root, /tests mounted read-only. execute-deliverable style.
set -u

LOG=/tmp/verify.log
: > "$LOG"
fails=0

fail() { echo "FAIL: $1" >> "$LOG"; fails=$((fails+1)); }
note() { echo "note: $1" >> "$LOG"; }

mkdir -p /logs/verifier
RWD=/logs/verifier/reward.txt
# crash-proof reward: default to 0 immediately; overwrite at the very end.
# Any abnormal termination (signal, unset var, wallclock kill) still leaves
# a reward file with 0.
echo 0 > "$RWD"
trap 'echo 0 > "$RWD"' INT TERM

# --- every deliverable must be present ---
for f in /app/setup.sh /app/status.json /app/pcap_to_netflow.py /app/answer.txt; do
    [ -e "$f" ] || fail "deliverable missing: $f"
done

# --- run the master provisioning deliverable (idempotent) ---
if [ -x /app/setup.sh ]; then
    bash /app/setup.sh >>"$LOG" 2>&1 || fail "setup.sh crashed"
else
    fail "setup.sh not executable"
fi
sleep 2

# poll briefly for the cluster report to go healthy (reporter refreshes every 2s)
for _ in $(seq 1 15); do
    healthy=$(python3 -c "import json;print(json.load(open('/app/status.json')).get('healthy'),end='')" 2>/dev/null)
    [ "$healthy" = "True" ] && break
    sleep 1
done

# === 1. cluster: three peers alive on the RPC ports ===
for p in 18081 18082 18083; do
    nc -z -w 5 127.0.0.1 "$p" >>"$LOG" 2>&1 || fail "peer port $p not listening"
done

# reporter HTTP endpoint returns a healthy report
rep=
for _ in $(seq 1 10); do
    rep=$(curl -s --max-time 2 http://127.0.0.1:18490/ 2>>"$LOG" || true)
    echo "$rep" | grep -q '"healthy":true' && break
    sleep 1
done
echo "$rep" | grep -q '"healthy":true' || fail "reporter HTTP endpoint no healthy report"

# /app/status.json must report a healthy, complete cluster
if [ -s /app/status.json ]; then
    python3 - <<'PY'
import json
s=json.load(open('/app/status.json'))
ok = s.get('cluster')=='relay-bank' and s.get('healthy') is True \
     and len(s.get('members', []))==3 and s.get('expected')==3 \
     and all(n.get('up') is True for n in s.get('members', [])) \
     and sorted(n.get('port') for n in s['members'])==[18081,18082,18083]
open('/tmp/ok_status','w').write('1' if ok else '0')
PY
    [ "$(cat /tmp/ok_status 2>/dev/null)" = "1" ] || fail "status.json not healthy(3 up nodes)"
else
    fail "/app/status.json missing/empty"
fi

# --- 2. name resolution + hostname persist via files ---
getent hosts relay-bank.internal 2>>"$LOG" | grep -q '10.9.9.77' || fail "relay-bank.internal does not resolve"
getent hosts relay-bank-vnode 2>>"$LOG" | grep -q '10.9.9.77' || fail "relay-bank-vnode does not resolve"
grep -q 'relay-bank-vnode' /etc/hostname 2>/dev/null || fail "hostname not persisted in /etc/hostname"
grep -q 'relay-bank.internal' /etc/hosts 2>/dev/null || fail "hosts fix not persisted"

# --- 3. mailing-list canonical config + local delivery ---
[ -f /etc/postfix/relay_mapping ] || fail "canonical relay_mapping missing"
grep -q 'relay.briefs@relay.internal' /etc/postfix/relay_mapping 2>/dev/null || fail "list not in relay_mapping"
grep -q 'local:mailreader' /etc/postfix/relay_mapping 2>/dev/null || fail "list not mapped to local mailreader"
[ -f /etc/postfix/relay_mapping.db ] || fail "relay_mapping.db not rebuilt (postmap)"
grep -q 'transport_maps' /etc/postfix/main.cf 2>/dev/null || fail "transport_maps not declared"
grep -q 'relay_mapping' /etc/postfix/main.cf 2>/dev/null || fail "main.cf does not reference relay_mapping"
grep -q '^mailreader:' /etc/aliases 2>/dev/null || fail "no mailreader alias"
[ -f /etc/aliases.db ] || fail "aliases.db not rebuilt (postalias)"
getent passwd mailreader >/dev/null 2>&1 || fail "mailreader account missing"

# --- 4. pcap -> flows: visible + hidden + malformed ---
# Compare two JSON flow tables. Never tracebacks: read/parse failures are
# reported as a clean note in the log and yield a non-zero exit (FAIL).
pycomp() {
python3 - "$1" "$2" <<'PY' 2>>"$LOG"
import json, sys
try:
    a = json.load(open(sys.argv[1]))
    b = json.load(open(sys.argv[2]))
except Exception as exc:
    sys.stderr.write("pycomp: cannot compare %s vs %s: %s\n"
                     % (sys.argv[1], sys.argv[2], exc))
    sys.exit(1)
sys.exit(0 if a == b else 1)
PY
}

python3 /app/pcap_to_netflow.py /app/fixtures/traffic.pcap /tmp/vflows.json >/dev/null 2>>"$LOG" || fail "visible pcap parse crash"
if pycomp /tmp/vflows.json /tests/expected.json; then :; else fail "visible flows != expected"; fi

# hidden pcap generalization: every hidden capture mounted at verify time
# must parse to its sibling <name>.json expectation. Driven by the actual
# files on disk so a naming mismatch can never silently skip the check.
hidden_checked=0
for hp in /tests/hidden/*.pcap; do
    [ -f "$hp" ] || continue                 # no hidden captures mounted
    case "${hp##*/}" in
        truncated.pcap) continue ;;           # malformed fixture, exercised below
    esac
    hjs="${hp%.pcap}.json"
    hname="${hp##*/}"
    [ -f "$hjs" ] || { fail "no expectation $hjs for hidden capture $hp"; continue; }
    out="/tmp/${hname%.pcap}.json"
    if ! python3 /app/pcap_to_netflow.py "$hp" "$out" >/dev/null 2>>"$LOG"; then
        fail "hidden $hname parse crash"
        continue
    fi
    pycomp "$out" "$hjs" || fail "hidden $hname flows != expected"
    hidden_checked=$((hidden_checked+1))
done
[ "$hidden_checked" -ge 1 ] || fail "no hidden pcap cases verified (generalization untested)"

# malformed inputs must fail gracefully (non-zero, no output file)
for bad in garbage.bin truncated.pcap; do
    rm -f /tmp/bad.json
    if python3 /app/pcap_to_netflow.py "/tests/hidden/$bad" /tmp/bad.json >/tmp/bad.out 2>&1; then
        fail "malformed $bad accepted (should exit non-zero)"
    else
        [ ! -e /tmp/bad.json ] || fail "malformed $bad created output file"
    fi
done

# --- verbatim ending text ---
cmp -s /app/answer.txt /app/fixtures/valediction.txt || fail "answer.txt not byte-identical to valediction"

# --- persisted login shell ---
[ "$(getent passwd mailreader | cut -d: -f7)" = "/bin/bash" ] || fail "mailreader shell not /bin/bash"

note "total failures: $fails"
if [ "$fails" = "0" ]; then
    echo "1" > "$RWD"
else
    echo "0" > "$RWD"
fi
# normal exit does not fire the INT/TERM guards, so the final reward
# written above is authoritative; signals during the run left 0 in place
echo "REWARD=$(cat "$RWD")"
exit 0