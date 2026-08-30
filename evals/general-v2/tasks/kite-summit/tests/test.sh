#!/usr/bin/env bash
# kite-summit verifier: executes every deliverable and writes a numeric reward.
set -u
rm -rf /tmp/verify
mkdir -p /tmp/verify /logs/verifier
FAIL=0
ok()   { echo "[ok]   $1"; }
bad()  { echo "[FAIL] $1"; FAIL=1; }

touch_loc() { python3 -c "import site;print(site.getsitepackages()[0])"; }

echo "================= verifier kite-summit ================="

# ---------------------------------------------------------------------------
# Subtask 1: gate network (/app/gate_net.txt, /app/gate_validate.py)
# ---------------------------------------------------------------------------
if [ ! -f /app/gate_net.txt ] || [ ! -f /app/gate_validate.py ]; then
    bad "missing gate deliverables"
else
    # structural: VERSION/BITS header, OUTPUT present, node-line count <= NODES cap
    python3 - "$@" <<'PY'
import sys, re
lines=[l.split('#')[0].strip() for l in open('/app/gate_net.txt') if l.strip()]
lines=[l for l in lines if l]
ver=[l for l in lines if l.startswith('VERSION')]
bits=[l for l in lines if l.startswith('BITS')]
nodes=[l for l in lines if l.startswith('NODES')]
out=[l for l in lines if l.startswith('OUTPUT')]
node_lines=[l for l in lines if re.match(r'^\d+\s*=', l)]
cap=int(nodes[0].split()[1]) if nodes else 0
ids=[int(re.match(r'^(\d+)',l).group(1)) for l in node_lines]
ok= (ver and ver[0].split()[1]=='1' and bits and bits[0].split()[1]=='32'
     and out and node_lines and cap>0 and len(node_lines)<=cap
     and len(ids)==len(set(ids)) and ids==sorted(ids) and ids[0]==0)
if not ok:
    print('STRUCT_FAIL', 'ver',ver,'bits',bits,'out',out,'cap',cap,'count',len(node_lines))
    sys.exit(1)
print('STRUCT_OK nodes=%d cap=%d'%(len(node_lines),cap))
PY
    if [ $? -ne 0 ]; then bad "gate_net.txt structure"; else ok "gate_net.txt structure (line cap ok)"; fi

    for vec in /tests/hidden/gate/vec_*.txt; do
        if ! python3 /app/gate_validate.py "$vec" >/tmp/verify/gv.out 2>&1; then
            bad "gate_validate.py on $(basename "$vec")"
            cat /tmp/verify/gv.out | head -5
        elif ! grep -q PASS /tmp/verify/gv.out; then
            bad "gate_validate.py no PASS on $(basename "$vec")"
        else
            ok "gate_validate.py PASS on $(basename "$vec")"
        fi
        # independent re-evaluation of the network itself
        if ! python3 /tests/_gate_sim.py "$vec" >/tmp/verify/gs.out 2>&1; then
            bad "independent gate eval on $(basename "$vec")"
            cat /tmp/verify/gs.out | head -5
        else
            ok "independent gate eval PASS on $(basename "$vec")"
        fi
    done
fi

# ---------------------------------------------------------------------------
# Subtask 2: compressor (/app/compress.py, /app/payload.bin)
# ---------------------------------------------------------------------------
if [ ! -f /app/compress.py ] || [ ! -f /app/payload.bin ]; then
    bad "missing compressor deliverables"
else
    PAYLOAD_BUDGET=2800
    psz=$(stat -c%s /app/payload.bin 2>/dev/null || echo -1)
    if [ "$psz" -ge "$PAYLOAD_BUDGET" ]; then bad "payload.bin size $psz >= $PAYLOAD_BUDGET"; else ok "payload.bin size $psz < $PAYLOAD_BUDGET"; fi
    if ! python3 /tests/_compr_check.py /app/payload.bin /app/sample.dat >/tmp/verify/pay.out 2>&1; then
        bad "payload.bin decode != sample.dat"
        cat /tmp/verify/pay.out | head -3
    else
        ok "payload.bin decodes to sample.dat"
    fi

    if [ -f /tests/hidden/compress/manifest.json ]; then
        python3 - "$@" <<'PY'
import json, os, subprocess, sys
manifest=json.load(open('/tests/hidden/compress/manifest.json'))
bad=0
for blob, budget in manifest.items():
    src=os.path.join('/tests/hidden/compress',blob)
    out='/tmp/verify/compr.bin'
    dec='/tmp/verify/compr.dec'
    r=subprocess.run(['python3','/app/compress.py',src,out],capture_output=True)
    if r.returncode!=0:
        print('RUN_FAIL',blob,r.stderr.decode()[:200]); bad=1; continue
    if not os.path.exists(out):
        print('NO_OUT',blob); bad=1; continue
    sz=os.path.getsize(out)
    ok_sz = sz < budget
    chk=subprocess.run(['python3','/tests/_compr_check.py',out,src],capture_output=True)
    rt=subprocess.run(['python3','/app/compress.py','--decompress',out,dec],capture_output=True)
    match_agent = (rt.returncode==0 and os.path.exists(dec)
                   and open(dec,'rb').read()==open(src,'rb').read())
    if not ok_sz: print('SIZE_FAIL',blob,sz,'budget',budget)
    if chk.returncode!=0: print('DECODE_FAIL',blob,chk.stdout.decode()[:200],chk.stderr.decode()[:200])
    if not match_agent: print('AGENT_DECODE_FAIL',blob)
    if not (ok_sz and chk.returncode==0 and match_agent): bad=1
    else: print('HIDDEN_OK',blob,sz,'budget',budget)
sys.exit(bad)
PY
        if [ $? -ne 0 ]; then bad "hidden compress blobs"; else ok "all hidden compress blobs"; fi
    else
        bad "no hidden compress manifest"
    fi
fi

# ---------------------------------------------------------------------------
# Subtask 3: footprint (/app/footprint_report.txt)
# ---------------------------------------------------------------------------
if [ ! -f /app/footprint_report.txt ]; then
    bad "missing footprint_report.txt"
else
    if python3 /tests/_foot_check.py >/tmp/verify/foot.out 2>&1; then
        ok "footprint_report.txt consistent and within budget"
    else
        bad "footprint_report.txt"
        cat /tmp/verify/foot.out | head -5
    fi
fi

# ---------------------------------------------------------------------------
echo "============================================================"
if [ "$FAIL" -eq 0 ]; then
    echo "REWARD=1"
    echo 1 > /logs/verifier/reward.txt
else
    echo "REWARD=0"
    echo 0 > /logs/verifier/reward.txt
fi
exit 0
