#!/bin/bash
# /app/run.sh — iris-ledge driver.
#
# Boots a tiny busybox guest under QEMU software emulation (TCG, no KVM) with a
# monitor console and a serial TCP redirect, shares the container root via 9p so
# the guest can chroot into it and compile a static assembly-level program, runs
# that program to a known exit status, drives an in-guest renderer to completion
# (writing a P6 PPM frame), then leaves the emulator running in the background.
#
# Usage: /app/run.sh [SCENARIO_JSON] [OUTDIR]
set -u

SCN="${1:-/app/scenario-main.json}"
OUT="${2:-/app}"

# ---- parse scenario -------------------------------------------------------
read_scn() { python3 -c "import json,sys;print(json.load(open('$SCN')).get('$1',''))"; }
ES=$(read_scn exit_status)
W=$(read_scn width)
H=$(read_scn height)
SD=$(read_scn seed)
MP=$(read_scn monitor_port)
SP=$(read_scn serial_port)
NAME=$(read_scn name); [ -n "$NAME" ] || NAME=scenario
FRAME=$(read_scn frame); [ -n "$FRAME" ] || FRAME=frame.pgm

if [ -z "$ES" ] || [ -z "$W" ] || [ -z "$H" ] || [ -z "$MP" ] || [ -z "$SP" ]; then
  echo "iris run.sh: bad scenario file $SCN" >&2
  exit 2
fi

# ---- clean any stale qemu, prepare the shared work area -------------------
pkill -f qemu-system-x86_64 2>/dev/null
sleep 1
mkdir -p /opt/iris/work
rm -rf /opt/iris/work/*
cp "$SCN" /opt/iris/scenario.json

# guest-side driver: runs INSIDE the emulated guest (via chroot into the 9p
# shared container root). It compiles a static inline-asm program, runs it,
# renders a P6 PPM frame from width/height/seed, and writes results to the
# shared /opt/iris/work volume so the host can read them.
cat > /opt/iris/guest_work.sh <<'GWEOF'
#!/bin/bash
set -u
cd /opt/iris || exit 9
PY=python3
SC=/opt/iris/scenario.json
ES=$($PY -c "import json;print(json.load(open('$SC'))['exit_status'])")
W=$($PY -c "import json;print(json.load(open('$SC'))['width'])")
H=$($PY -c "import json;print(json.load(open('$SC'))['height'])")
SD=$($PY -c "import json;print(json.load(open('$SC'))['seed'])")

# 1) statically-linked assembly-level program with a known exit status
cat > /opt/iris/prog.c <<PEOF
int main(void){ int x; asm("movl \$$ES,%0" : "=r"(x)); return x; }
PEOF
gcc -static -O1 -o /opt/iris/prog /opt/iris/prog.c
/opt/iris/prog; PE=$?
echo "$PE" > /opt/iris/work/prog.exit

# 2) renderer driven to first-frame completion (P6 PPM), seeded deterministically
cat > /opt/iris/render.c <<REOF
#include <stdio.h>
#include <stdlib.h>
int main(int argc,char**argv){
  int W = atoi(argv[1]); int H = atoi(argv[2]); unsigned SD = (unsigned)atoi(argv[3]);
  if (W<1||H<1||W>1024||H>1024) return 2;
  unsigned char *p = malloc((size_t)W*H*3);
  unsigned s = SD;
  for (int y=0;y<H;y++) for (int x=0;x<W;x++){
    s = s*1664525u + 1013904223u;
    int i=(y*W+x)*3;
    p[i]=(unsigned char)((s>>16)&0xff); p[i+1]=(unsigned char)((s>>8)&0xff); p[i+2]=(unsigned char)(s&0xff);
  }
  FILE*f=fopen("/opt/iris/work/frame.ppm","wb");
  if(!f) return 3;
  fprintf(f,"P6\n%d %d\n255\n",W,H);
  fwrite(p,1,(size_t)W*H*3,f);
  fclose(f); free(p);
  return 0;
}
REOF
gcc -static -O2 -o /opt/iris/render /opt/iris/render.c
/opt/iris/render "$W" "$H" "$SD"

# done marker + captured prog exit
echo "PROG_EXIT=$PE" > /opt/iris/work/result_raw
echo "RENDER_OK"     >> /opt/iris/work/result_raw
echo done
GWEOF
chmod +x /opt/iris/guest_work.sh

# ---- boot the tiny guest in the background ---------------------------------
nohup qemu-system-x86_64 -machine pc -m 1024 -smp 2 \
  -kernel /app/vmlinuz -initrd /app/guest-initrd.cpio.gz \
  -append "console=ttyS0 panic=-1 rdinit=/init" \
  -nographic -no-reboot -no-shutdown -accel tcg \
  -virtfs local,path=/,mount_tag=hostroot,security_model=none \
  -monitor telnet:127.0.0.1:$MP,server,nowait \
  -serial tcp:127.0.0.1:$SP,server,nowait \
  > /opt/iris/qemu.log 2>&1 &
QP=$!

# ---- wait (bounded) for the guest to finish its work ------------------------
for i in $(seq 1 180); do
  if [ -f /opt/iris/work/result_raw ]; then break; fi
  sleep 1
done

PE=$(cat /opt/iris/work/prog.exit 2>/dev/null || echo -1)
cp /opt/iris/work/frame.ppm "$OUT/$FRAME" 2>/dev/null
# frame_bytes = PPM *payload* byte count (invariant to the header length)
FB=$(python3 - "$OUT/$FRAME" <<'LENEOF'
import sys

try:
    d = open(sys.argv[1], 'rb').read().split(b'\n', 3)
    print(len(d[3]) if len(d) >= 4 else -1)
except Exception:
    print(-1)
LENEOF
)

# ---- self-checks: serial liveness + monitor console -------------------------
SEROK=0; MONOK=0
if timeout 10 bash -c "exec 3<>/dev/tcp/127.0.0.1/$SP; sleep 1; printf 'echo SER_LIVENESS_OK\\n' >&3; (timeout 6 dd bs=1 count=16384 <&3 2>/dev/null)" 2>/dev/null \
   | grep -q SER_LIVENESS_OK; then SEROK=1; fi
if timeout 4 bash -c "exec 3<>/dev/tcp/127.0.0.1/$MP; printf 'info cpus\n' >&3; timeout 2 head -c 300 <&3" 2>/dev/null \
   | grep -qiE 'cpu|qemu|pc='; then MONOK=1; fi

kill -0 "$QP" 2>/dev/null && ALIVE=1 || ALIVE=0
PE_OK=0; [ "$PE" = "$ES" ] && PE_OK=1
EXP=$((W*H*3)); ROK=0; [ "$FB" = "$EXP" ] && ROK=1

python3 - "$OUT" "$NAME" "$ES" "$PE" "$PE_OK" "$W" "$H" "$SD" "$FRAME" "$FB" "$ROK" "$MP" "$SP" "$SEROK" "$MONOK" "$QP" "$ALIVE" <<'PEOF'
import json, sys
out,name,es,pe,peok,W,H,SD,F,FB,rok,MP,SP,serok,monok,qp,alive = sys.argv[1:]
d=dict(
  task="iris-ledge", scenario=name,
  exit_status=int(es), program_exit=int(pe), program_exit_ok=(peok=="1"),
  compiled_static=True,
  render_ok=(rok=="1"), frame=F,
  frame_width=int(W), frame_height=int(H), frame_seed=int(SD), frame_bytes=int(FB),
  monitor_port=int(MP), serial_port=int(SP),
  monitor_ok=(monok=="1"), serial_ok=(serok=="1"),
  qemu_pid=int(qp), qemu_alive=(alive=="1"), background=True,
)
json.dump(d, open(f"{out}/result.json","w"), indent=2)
PEOF

echo "iris run.sh: scenario=$NAME prog_exit=$PE frame_bytes=$FB qemu_alive=$ALIVE"
exit 0
