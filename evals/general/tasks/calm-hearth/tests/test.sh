#!/usr/bin/env bash
# calm-hearth verifier (executes-deliverable).
# /app  = agent deliverable work; /tests = read-only (hidden mounted at /tests/hidden)
# Executes every deliverable; reward written to /logs/verifier/reward.txt.
set -uo pipefail
mkdir -p /logs/verifier
reward=1
fail(){ echo "FAIL: $*" >&2; reward=0; }

# ---- 0. deliverables present ------------------------------------------ #
[ -x /app/fixedheap ]  || fail "missing/not executable /app/fixedheap"
[ -f /app/callffi.py ] || fail "missing /app/callffi.py"
[ -f /app/reimpl.py ]  || fail "missing /app/reimpl.py"
[ -f /app/notes.md ]   || fail "missing /app/notes.md"
[ -f /app/user.cpp ]   || fail "missing /app/user.cpp"
[ -f /app/main.cpp ]   || fail "missing /app/main.cpp"
[ -f /app/Makefile ]   || fail "missing /app/Makefile"
[ -f /app/libtransform.so ] || fail "missing /app/libtransform.so"
[ -x /app/target/render ]   || fail "missing /app/target/render"
if [ "$reward" -eq 0 ]; then echo "0" >/logs/verifier/reward.txt; echo "final-reward=0"; exit 0; fi

# ---- 1. protected fixtures must remain byte-identical ------------------ #
MAIN_HASH=$(sha256sum /app/main.cpp | cut -d' ' -f1)
MK_HASH=$(sha256sum /app/Makefile | cut -d' ' -f1)
[ "$MAIN_HASH" = "6a87e618faa8d76c7c5e72593c6bf5f1466b1546ea5e69eb943554b9ee063f15" ] \
  || fail "main.cpp was modified (protected)"
[ "$MK_HASH" = "4feaf09ad093cbc022eccd97bb5763d0b2c55f0d92ab0dd97fe9257c1082d78e" ] \
  || fail "Makefile was modified (protected)"
[ "$reward" -eq 0 ] && { echo "0" >/logs/verifier/reward.txt; echo "final-reward=0"; exit 0; }

# ---- 2. rebuild the fixed heap from the agent's source ------------------ #
if (cd /app && make clean >/dev/null 2>&1 && make) >/tmp/heap_build.log 2>&1; then
  [ -x /app/fixedheap ] || fail "make did not produce /app/fixedheap"
else
  fail "make (rebuild of fixedheap) failed: $(tail -5 /tmp/heap_build.log)"
fi
[ "$reward" -eq 0 ] && { echo "0" >/logs/verifier/reward.txt; echo "final-reward=0"; exit 0; }

# ---- 3+4+5 hidden cases across all three subtasks ----------------------- #
PY=$(cat <<'PY'
import glob, os, subprocess, sys, ctypes

K=[1,2,1,2,4,2,1,2,1]

def ref_checksum(path):
    live=[]  # (n, fill, is_live)
    with open(path) as f:
        for line in f:
            t=line.split()
            if not t: continue
            op=t[0][0]
            if op=='A' and len(t)>=2:
                try: n=int(t[1])
                except ValueError: continue
                live.append([n,0,True])
            elif op=='F':
                for i in range(len(live)-1,-1,-1):
                    if live[i][2]:
                        live[i][2]=False; break
            elif op=='W' and len(t)>=2:
                try: v=int(t[1])
                except ValueError: continue
                for i in range(len(live)-1,-1,-1):
                    if live[i][2]:
                        live[i][1]=v&0xff; break
    return sum(n*f for n,f,al in live if al)

def ref_scramble(b):
    out=[]; s=0
    for x in b:
        v=((x*31+17)&0xff); out.append(v); s+=v
    return s+424242, bytes(out)

def ref_render(path):
    with open(path) as f:
        H,W=map(int,f.readline().split())
        g=[[int(x)&0xff for x in f.readline().split()] for _ in range(H)]
    rows=[]
    for y in range(H):
        row=[]
        for x in range(W):
            acc=0
            for dy in range(3):
                sy=max(0,min(H-1,y+dy-1))
                for dx in range(3):
                    sx=max(0,min(W-1,x+dx-1))
                    acc+=g[sy][sx]*K[dy*3+dx]
            row.append(str(acc//16))
        rows.append(' '.join(row))
    return '\n'.join(rows)+'\n' if rows else ''

cases=sorted(glob.glob('/tests/hidden/case*'))
if not cases:
    print("NO HIDDEN CASES"); sys.exit(0)
fails=[]
for d in cases:
    # --- heap: no crash + exact checksum ---
    wf=os.path.join(d,'workload.heap')
    if os.path.isfile(wf):
        exp=ref_checksum(wf)
        r=subprocess.run(['/app/fixedheap',wf],capture_output=True,text=True,timeout=60)
        if r.returncode!=0:
            fails.append(f"{d}: heap crashed/errored rc={r.returncode} ({r.stderr.strip()[:80]})")
        else:
            got=r.stdout.strip().split()[-1] if r.stdout.strip() else ''
            want=f"HEAP-OK {exp}"
            if r.stdout.strip()!=want:
                fails.append(f"{d}: heap got {r.stdout.strip()!r} want {want!r}")
    # --- ffi: retval + transformed output (empty file case too) ---
    for tag in ('ffi.dat','ffi_empty.dat'):
        ff=os.path.join(d,tag)
        if not os.path.isfile(ff): continue
        data=open(ff,'rb').read()
        er,eb=ref_scramble(data)
        out=os.path.join('/tmp',f"ffi_out_{os.path.basename(d)}_{tag}")
        r=subprocess.run(['python3','/app/callffi.py',ff,out],capture_output=True,text=True,timeout=60)
        if r.returncode!=0:
            fails.append(f"{d}/{tag}: callffi.py rc={r.returncode} ({r.stderr.strip()[:80]})"); continue
        wantout=f"FFI-RET {er}"
        if r.stdout.strip()!=wantout:
            fails.append(f"{d}/{tag}: ffI ret got {r.stdout.strip()!r} want {wantout!r}")
        if os.path.isfile(out) and open(out,'rb').read()!=eb:
            fails.append(f"{d}/{tag}: ffI transformed bytes mismatch")
    # --- renderer reimplementation: exact stdout equality ---
    gf=os.path.join(d,'grid.txt')
    if os.path.isfile(gf):
        ref=ref_render(gf)
        rrender=subprocess.run(['/app/target/render',gf],capture_output=True,timeout=60)
        rreimpl=subprocess.run(['python3','/app/reimpl.py',gf],capture_output=True,timeout=60)
        if rreimpl.returncode!=0:
            fails.append(f"{d}: reimpl.py rc={rreimpl.returncode} ({rreimpl.stderr.strip()[:80]})")
        elif rrender.stdout!=rreimpl.stdout:
            fails.append(f"{d}/grid: reimpl stdout != native render stdout (len {len(rreimpl.stdout)} vs {len(rrender.stdout)})")
        elif ref.encode()!=rreimpl.stdout:
            fails.append(f"{d}/grid: reference mismatch")

if fails:
    print(" ; ".join(fails)); sys.exit(1)
print("HIDDEN-CASES-PASS")
PY
)
if python3 -c "$PY"; then :; else fail "hidden functional checks failed"; fi
[ "$reward" -eq 0 ] && { echo "0" >/logs/verifier/reward.txt; echo "final-reward=0"; exit 0; }

# ---- 6. leak profile: valgrind over one arithmetic workload ------------- #
WD=/tmp/valgrid.heap
cat > "$WD" <<'VVV'
A 250000
W 66
A 120000
W 33
F
A 90000
W 21
A 40000
F
W 9
W
W
VVV
if command -v valgrind >/dev/null 2>&1; then
  vg=$(valgrind --error-exitcode=99 --leak-check=full /app/fixedheap "$WD" 2>&1)
  echo "$vg" | grep -q "ERROR SUMMARY: 0 errors" || fail "valgrind reported errors"
  if echo "$vg" | grep -Eq "definitely lost: [1-9]"; then fail "valgrind found definite leaks"; fi
  echo "$vg" | grep -q "^HEAP-OK " || fail "valgrind run produced no HEAP-OK line"
else
  fail "valgrind not installed"
fi

# ---- finalize ------------------------------------------------------------ #
echo "final-reward=$reward"
echo "$reward" >/logs/verifier/reward.txt
exit 0