#!/bin/bash
# Verifier for fern-terrace. Runs after the agent finishes (same container, so the
# emulator the agent left running is still alive). Writes reward to /logs/verifier/reward.txt.
set -u
REWARD=1
fail() { echo "VERIFY-FAIL: $1"; REWARD=0; }

ISOCHECK() { # $1 iso ; returns 0 if it looks like an ISO9660 image
    [ -f "$1" ] || return 1
    # ISO9660 magic "CD001" lives at byte 0x8001
    local m; m=$(dd if="$1" bs=1 skip=$((0x8001)) count=5 2>/dev/null)
    [ "$m" = "CD001" ]
}

INDEPEXTRACT() { # $1 diskimg $2 marker_path $3 outfile
    python3 - "$1" "$2" "$3" <<'PY'
import sys,struct,os,subprocess
disk,mpath,out=sys.argv[1],sys.argv[2],sys.argv[3]
b=open(disk,'rb').read(512); e=b[446:462]
typ=e[4]; lba=struct.unpack('<I',e[8:12])[0]; ns=struct.unpack('<I',e[12:16])[0]
if typ!=0x83: sys.exit(1)
part=out+'.p'
with open(disk,'rb') as r, open(part,'wb') as w:
    r.seek(lba*512); w.write(r.read(ns*512))
subprocess.run(['debugfs','-R','dump %s %s'%(mpath,out),part],
               check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
os.unlink(part)
PY
}

SSHCMD() { # $1 port $2 password ; runs every + returns the guest servicetoken line
    sshpass -p "$2" ssh -p "$1" -oStrictHostKeyChecking=no \
        -oUserKnownHostsFile=/dev/null -oConnectTimeout=2 \
        root@127.0.0.1 "cat /etc/service-token"
}

QALIVE() { # $1 host_port ; emulator still running?
    pgrep -f "hostfwd=tcp:127.0.0.1:$1-" >/dev/null
}

check_guest() { # $1 outdir $2 expected_token $3 expected_marker $4 port $5 password
    local od exp_tok exp_m p pw
    od="$1"; exp_tok="$2"; exp_m="$3"; p="$4"; pw="$5"
    # serial.log boot markers
    grep -q "FERN-BOOT-READY"        "$od/serial.log" 2>/dev/null || { fail "no FERN-BOOT-READY in $od/serial.log"; }
    grep -q "FERN-SERVICE-TOKEN=$exp_tok" "$od/serial.log" 2>/dev/null || { fail "token missing in serial.log"; }
    # guest.iso present and iso9660
    ISOCHECK "$od/guest.iso" || { fail "guest.iso not a valid ISO9660 image"; }
    # recovered marker file
    local got; got=$(cat "$od/extracted/marker" 2>/dev/null)
    [ "$got" = "$exp_m" ] || { fail "recovered marker mismatch: got=$got expected=$exp_m"; }
    # independent re-extraction of the disk at its partition offset
    local ind; ind=$(mktemp)
    if INDEPEXTRACT "$od/disk.img" /media/data/marker "$ind"; then
        local ic; ic=$(cat "$ind")
        [ "$ic" = "$exp_m" ] || { fail "independent partition re-extract mismatch: $ic vs $exp_m"; }
    else
        fail "independent partition re-extract failed for $od/disk.img"
    fi
    rm -f "$ind"
    # password SSH into the running guest + background persistence
    local got_tok
    got_tok=$(SSHCMD "$p" "$pw" 2>/dev/null)
    [ "$got_tok" = "$exp_tok" ] || { fail "ssh token mismatch: got=$got_tok expected=$exp_tok"; }
    QALIVE "$p" || { fail "emulator for port $p is not alive after ssh"; }
}

# ---------------- visible case ----------------
if [ ! -x /app/build_guest.sh ]; then
    fail "missing deliverable /app/build_guest.sh"
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi
[ -f /app/guest.iso ] && [ -f /app/serial.log ] || fail "missing visible deliverables /app/guest.iso or /app/serial.log"
if [ "$REWARD" = 1 ]; then
    check_guest /app \
        "fern-terrace-morning-mist-4811" \
        "wpb-fernterrace-seed-1024" \
        2720 "zephyr-willow-2291"
fi

# ---------------- hidden cases ----------------
IMG=$(mktemp -d)
for c in "$(dirname "$0")"/hidden/case_*; do
    [ -d "$c" ] || continue
    [ "$REWARD" = 1 ] || break
    case_name=$(basename "$c")
    echo ">>> hidden case: $case_name"
    cjson="$c/case.json"
    # collect expectations from the hidden profile
    eval "$(python3 - "$cjson" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
print('hk=%r'%d['hostname'])
print('htok=%r'%d['service_token'])
print('hmark=%r'%d['marker_expected'])
print('hport=%r'%d['port'])
print('hpw=%r'%d['password'])
print('hmpath=%r'%d['marker_path'])
PY
)"
    hout="$IMG/$case_name"; mkdir -p "$hout"
    # ensure case.json references the provided disk path
    python3 - "$cjson" "$c" "$hout/case.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); d['disk']=sys.argv[2]+'/disk.img'; json.dump(d,open(sys.argv[3],'w'))
PY
    if ! bash /app/build_guest.sh "$hout/case.json" "$hout" >"$hout/build.log" 2>&1; then
        fail "builder failed for hidden case $case_name"
        break
    fi
    check_guest "$hout" "$htok" "$hmark" "$hport" "$hpw"
    QALIVE "$hport" && pkill -9 -f "hostfwd=tcp:127.0.0.1:$hport-" 2>/dev/null
    sleep 1
done
rm -rf "$IMG"

[ -d /logs/verifier ] || mkdir -p /logs/verifier
echo "$REWARD" > /logs/verifier/reward.txt
echo "REWARD=$REWARD"
exit 0
