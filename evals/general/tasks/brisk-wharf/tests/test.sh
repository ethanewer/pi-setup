#!/usr/bin/env bash
# brisk-wharf verifier. Runs as root after the agent finishes; /tests is
# mounted read-only. Must write a numeric reward to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
E=/app
H=/tests/hidden
pass=0
total=0
fail(){ echo "FAIL: $*"; }

# ---------------------------------------------------------------- deliverable presence
total=$((total+1))
if [ -f "/app/serve.py" ] && [ -x "/app/serve.py" ]; then pass=$((pass+1)); else fail "serve.py missing/not executable"; fi
total=$((total+1))
if [ -f "/app/mpi_main.c" ]; then pass=$((pass+1)); else fail "mpi_main.c missing"; fi
total=$((total+1))
if [ -d "/app/markers" ]; then pass=$((pass+1)); else fail "markers dir missing"; fi

# ---------------------------------------------------------------- compile helpers
if [ ! -x "/app/protocol_server" ]; then
  ( cd /app && gcc /app/protocol/server.c -o /app/protocol_server -lssl -lcrypto ) 2>/dev/null
fi
mpicc -O2 "/app/mpi_main.c" -o /app/mpi_agg 2>/dev/null

# ---------------------------------------------------------------- netflow reference parser
cat > /tmp/nfparse.py <<'PY'
import socket,struct,sys
H=">HHIIIIBBH"; R=">IIIHHIIIIHHBBBBHHBBH"
def ip(i): return socket.inet_ntoa(struct.pack(">I",i))
p=open(sys.argv[1],'rb').read()
off=0; dgs=[]
while off+24<=len(p):
    h=struct.unpack(H,p[off:off+24]); off+=24
    v,count,up,us,un,seq,et,ei,samp=h
    recs=[]
    for i in range(count):
        r=struct.unpack(R,p[off:off+48]); off+=48
        recs.append(r)
    dgs.append((dict(version=v,count=count,uptime=up,secs=us,nsecs=un,seq=seq),recs))
import json
print(json.dumps(dgs))
PY

# ---------------------------------------------------------------- helpers
svc(){ :; }
fetch_expected(){ :; }

SCENARIOS="scenario_alpha scenario_beta scenario_gamma"
PROT_PORTS="9201 9301 9401"
BUCKET_PORTS="9221 9321 9421"

i=0
for S in $SCENARIOS; do
  i=$((i+1))
  echo "== scenario $S =="
  SD="$H/$S"

  # ---- 1. MPI: parallel == serial on hidden fragments; markers prove workers
  rm -rf /tmp/ser /tmp/par; mkdir -p /tmp/ser /tmp/par
  if mpirun --allow-run-as-root --oversubscribe -np 1 /app/mpi_agg "$SD/fragments.txt" /tmp/ser >/dev/null 2>&1 \
     && mpirun --allow-run-as-root --oversubscribe -np 4 /app/mpi_agg "$SD/fragments.txt" /tmp/par >/dev/null 2>&1; then
     cat /tmp/ser/flows.rank*.txt 2>/dev/null | sort > /tmp/ser.txt
     cat /tmp/par/flows.rank*.txt 2>/dev/null | sort > /tmp/par.txt
     total=$((total+1))
     if cmp -s /tmp/ser.txt /tmp/par.txt && [ -s /tmp/ser.txt ]; then pass=$((pass+1)); else fail "MPI parallel!=serial ($S)"; fi
     total=$((total+1))
     mk=$(ls /app/markers/mpi_rank*.marker 2>/dev/null | wc -l)
     if [ "$mk" -ge 4 ]; then pass=$((pass+1)); else fail "MPI worker markers <4 ($S)"; fi
  else
     total=$((total+1)); fail "mpirun failed ($S)"; total=$((total+1)); fail "mpi markers ($S)"
  fi

  # ---- 2. gloo: world from file; check GLOO_SUM + per-rank markers
  WORLD=$(cat "$SD/gloo.world")
  GL=$(python3 -c "n=$WORLD; print(3*n*(n+1)//2)")
  OUT=$(python3 "/app/serve.py" train-gloo --world "$WORLD" 2>/dev/null)
  total=$((total+1))
  if echo "$OUT" | grep -q "GLOO_SUM=$GL"; then pass=$((pass+1)); else fail "gloo sum wrong ($S): $OUT"; fi
  total=$((total+1))
  nmark=0
  for r in $(seq 0 $((WORLD-1))); do [ -f "/app/markers/gloo_rank$r.marker" ] && nmark=$((nmark+1)); done
  if [ "$nmark" = "$WORLD" ]; then pass=$((pass+1)); else fail "gloo markers $nmark/$WORLD ($S)"; fi

  # ---- 3. netflow: export hidden flows, parse, check
  total=$((total+1))
  if python3 "/app/serve.py" export-netflow --in "$SD/flows.txt" --out /tmp/nf.bin >/dev/null 2>&1 \
     && [ -s /tmp/nf.bin ]; then
     echo "OK" >/dev/null
     pass=$((pass+1))
  else fail "netflow export failed ($S)"; fi
  total=$((total+1))
  if python3 /tmp/nfparse.py /tmp/nf.bin > /tmp/nf.json 2>/dev/null \
     && python3 - "$SD/flows.txt" /tmp/nf.json <<'PY'
import sys,json,struct,socket
flows=[l.strip() for l in open(sys.argv[1]) if l.strip()]
dgs=json.load(open(sys.argv[2]))
ok=True
dgs=[d for d in dgs if d[0]['count']>0]
if len(dgs)!=1 or dgs[0][0]['version']!=5: sys.exit(1)
h=dgs[0][0]; recs=dgs[0][1]
if h['count']!=len(flows): sys.exit(1)
if h['uptime']!=3000000 or h['secs']!=1700000000 or h['nsecs']!=0: sys.exit(2)
if h['seq']!=1: sys.exit(3)
def ip(i): return socket.inet_ntoa(struct.pack('>I',i))
n=len(flows)
for i,fl in enumerate(flows):
    f=fl.split(',')
    r=recs[i]
    if ip(r[0])!=f[0] or ip(r[1])!=f[1]: sys.exit(4)
    if r[9]!=int(f[2]) or r[10]!=int(f[3]) or r[13]!=int(f[4]): sys.exit(5)
    if r[5]!=int(f[5]) or r[6]!=int(f[6]): sys.exit(6)
    exp_first=3000000-(n-i)*500; exp_last=3000000-(n-1-i)*200
    if r[7]!=exp_first or r[8]!=exp_last: sys.exit(7)
sys.exit(0)
PY
  then pass=$((pass+1)); else fail "netflow parse/fields wrong ($S)"; fi

  # ---- 4. protocol RE: run server with hidden flows, fetch, compare
  PORT=$(echo $PROT_PORTS | cut -d' ' -f$i)
  ( /app/protocol_server "$PORT" "$SD/flows.txt" >/dev/null 2>&1 & echo $! > /tmp/srv.pid )
  sleep 1
  total=$((total+1))
  if python3 "/app/serve.py" fetch-flows --port "$PORT" --out /tmp/fetched.txt >/dev/null 2>&1 \
     && cmp -s /tmp/fetched.txt "$SD/flows.txt"; then
     pass=$((pass+1))
  else fail "protocol fetch mismatch ($S)"; fi
  kill "$(cat /tmp/srv.pid)" 2>/dev/null

  # ---- 5. S3 bucket: hidden bucket name on local emulated endpoint
  BNAME=$(cat "$SD/bucket.name")
  BPORT=$(echo $BUCKET_PORTS | cut -d' ' -f$i)
  total=$((total+1))
  BOUT=$(python3 "/app/serve.py" make-bucket --name "$BNAME" --port "$BPORT" 2>/dev/null)
  if echo "$BOUT" | grep -q "$BNAME CREATED" && echo "$BOUT" | grep -q "$BNAME"; then
     pass=$((pass+1))
  else fail "S3 bucket $BNAME not verified ($S)"; fi

  # ---- 6. mailing-list stack: bring up + verify
  MNAME=$(cat "$SD/mail.list")
  python3 "/app/serve.py" mail-init --list "$MNAME" >/dev/null 2>&1
  total=$((total+1))
  if postfix status >/dev/null 2>&1; then pass=$((pass+1)); else fail "postfix not running ($S)"; fi
  total=$((total+1))
  LD="/var/spool/mlmmj/$MNAME"
  if [ -d "$LD/control" ] && [ -d "$LD/text" ] && [ -d "$LD/incoming" ] && [ -f "$LD/index" ]; then
     pass=$((pass+1))
  else fail "mlmmj list $MNAME not initialized ($S)"; fi
  total=$((total+1))
  if postalias -q "$MNAME" /etc/aliases 2>/dev/null | grep -q "/usr/bin/mlmmj-receive -L $LD"; then
     pass=$((pass+1))
  else fail "alias not routed to mlmmj-receive ($S)"; fi
  total=$((total+1))
  TOK="MAIL-CHECK-$(date +%s%N)"
  if printf 'From: analyst@station.local\nTo: %s@localhost\nSubject: t\n\n%s\n' "$MNAME" "$TOK" \
        | /usr/bin/mlmmj-receive -L "$LD" >/dev/null 2>&1 \
     && grep -rl "$TOK" "$LD" >/dev/null 2>&1; then
     pass=$((pass+1))
  else fail "mlmmj list processor did not accept mail ($S)"; fi
done

echo "brisk-wharf verifier: pass=$pass total=$total"
reward=0
if [ "$total" -gt 0 ] && [ "$pass" = "$total" ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
echo "REWARD=$reward"
