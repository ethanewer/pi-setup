#!/bin/bash
# Arcadia (arid-orchid) verifier.
# ============================================================
# Checks every deliverable and re-runs the renderers against hidden scenes.
# reward.txt is 1 only if ALL required checks pass, else 0.
set -uo pipefail

REWARD_FILE=/logs/verifier/reward.txt
REF="$(cd "$(dirname "$0")" && pwd)/reference.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ALL_PASS=1
PY=""
fail(){ echo "FAIL: $*"; ALL_PASS=0; }

# ---------- shared python compare -------------------------------------------------
cat > "$TMP/compare.py" <<'PY'
import sys, subprocess, numpy as np
def read_pfm(p):
    with open(p,'rb') as f:
        assert f.readline().strip()==b'PF'
        w,h=map(int,f.readline().split())
        scale=f.readline()
        data=np.fromfile(f,dtype='<f4',count=w*h*3).reshape(h,w,3)
    return data.astype(np.float64)
def read_pgm(p):
    with open(p) as f:
        l=f.readline().strip()          # P2
        assert l.startswith(b'P') if isinstance(l,bytes) else l.startswith('P'), l
        w,h=map(int,f.readline().split())
        mx=int(f.readline())
        vals=[]
        for ln in f:
            for t in ln.split(): vals.append(float(t))
    a=np.array(vals,np.float64).reshape(h,w)
    return a
def ssim(a,b):
    # structural similarity (grayscale, 0..1) simple global window-free proxy:
    m=(a+b)/2.0
    mb=b-m; ma=a-m
    # normalized luminance+contrast cross correlation
    if a.std()<1e-6 and b.std()<1e-6:
        return 1.0
    cov=np.mean((a-a.mean())*(b-b.mean()))
    va=a.var(); vb=b.var(); den=np.sqrt(va*vb)+1e-9
    corr=cov/den
    lum=2*a.mean()*b.mean()/(a.mean()**2+b.mean()**2+1e-9)
    st=2*a.std()*b.std()/(a.std()**2+b.std()**2+1e-9)
    return lum*corr*st
if sys.argv[1]=='pfm':
    a=read_pfm(sys.argv[2]); b=read_pfm(sys.argv[3])
    R=ssim(a[...,0],b[...,0]); G=ssim(a[...,1],b[...,1]); B=ssim(a[...,2],b[...,2])
    print((R+G+B)/3.0)
elif sys.argv[1]=='pgm':
    a=read_pgm(sys.argv[2]); b=read_pgm(sys.argv[3])
    print(ssim(a,b))
elif sys.argv[1]=='mae':
    a=read_pfm(sys.argv[2]); b=read_pfm(sys.argv[3])
    print(float(np.mean(np.abs(a-b))))
PY

comp(){
    # comp <pfm|pgm> <got> <want>
    python3 "$TMP/compare.py" "$1" "$2" "$3"
}

# ---------- the recorded interpreter (C-31a82871 / ptr file) -----------------------
if [ ! -f /app/renderer_env.txt ]; then fail "missing renderer_env.txt"; 
elif [ "$(wc -l < /app/renderer_env.txt)" -ne 1 ]; then fail "renderer_env.txt not single line";
else
    PY=$(cat /app/renderer_env.txt)
    if [ -z "$PY" ] || [ ! -x "$PY" ]; then fail "recorded interpreter not executable: $PY";
    else
        if ! "$PY" -c 'import sys;sys.exit(0)' >/dev/null 2>&1; then fail "recorded interpreter does not run";
        else echo "ok: pointer interpreter runs ($PY)"; fi
    fi
fi

# ---------- C1: PNG icon (C-9d248ada) -------------------------------------------
if [ ! -f /app/out.png ] || [ ! -f /app/make_icon.py ]; then fail "missing out.png / make_icon.py"; 
else
    res=$(python3 - "$@" <<'PY'
from PIL import Image
import numpy as np,sys
p='/app/out.png'
im=Image.open(p)
im.load()
if im.format!='PNG':
    print('badformat'); sys.exit()
a=np.asarray(im.convert('RGB')).astype(np.float32)
print('%d %d %.2f'%(im.size[0],im.size[1],a.std()))
PY
)
    echo "icon: $res"
    w=$(echo "$res"|awk '{print $1}')
    h=$(echo "$res"|awk '{print $2}')
    s=$(echo "$res"|awk '{print $3}')
    if [ "$w" != "640" ] || [ "$h" != "420" ]; then fail "out.png wrong dims ($res)"; fi
    if [ -z "$res" ] || echo "$res"|grep -q badformat; then fail "out.png not a valid PNG"; fi
    if python3 -c "exit(0)" ; then :; fi
    okstd=$(python3 -c "print(1 if float('$s')>25 else 0)")
    if [ "$okstd" = "1" ]; then echo "ok icon raster variety"; else fail "icon lacks raster variety (std=$s)"; fi
    # phrase region: dark text pixels present near bottom-left band
    phr=$(python3 - <<'PY'
from PIL import Image
import numpy as np
im=np.asarray(Image.open('/app/out.png').convert('L')).astype(np.int16)
band=im[300:410, 0:260]
print('text', int((band<120).sum()))
PY
)
    ntxt=$(echo "$phr"|awk '{print $2}')
    if python3 -c "print(1 if int('$ntxt')>100 else 0)" | grep -q 1; then
        echo "ok icon phrase present ($ntxt dark px)"
    else fail "icon phrase text missing ($phr)"; fi
fi

# ---------- C2: C path tracer (C-1ef80084) --------------------------------------
if [ ! -f /app/ptrace.c ]; then fail "missing ptrace.c";
else
    bytes=$(wc -c < /app/ptrace.c)
    if [ "$bytes" -gt 20000 ]; then fail "ptrace.c source too large ($bytes bytes)";
    else echo "ok ptrace.c source-size $bytes"; fi
    # it must look like an actual sampler/intersector, not a baked image
    if ! grep -qiE 'mc_rand|rand|sample|mc_|cosine|intersect|disc|lambert' /app/ptrace.c; then
        fail "ptrace.c lacks ray/sampling code (baked?)"; else echo "ok ptrace.c has sampling code"; fi
    if gcc -O2 -o "$TMP/ptrace_build" /app/ptrace.c -lm >/dev/null 2>&1; then
        echo "ok ptrace.c compiles";
    else fail "ptrace.c does not compile"; fi
fi

# ---- run the default render and compare vs reference (C-3 files, C-2 default pf) --
# default deliverables
for f in /app/ptrace_img.pfm /app/scene_color.pfm /app/scene_depth.pgm; do
    if [ ! -s "$f" ]; then fail "missing default render $f"; fi
done

# golden default
GOLD="$TMP/default"
mkdir -p "$GOLD"
python3 "$REF" /app/scene.cfg "$GOLD/ref.pfm" "$GOLD/ref.pgm"

if [ -s /app/ptrace_img.pfm ]; then
    ss=$(comp pfm /app/ptrace_img.pfm "$GOLD/ref.pfm")
    echo "ptrace_img SSIM vs golden: $ss"
    if python3 -c "print(1 if float('$ss')>=0.90 else 0)" | grep -q 1; then
        echo "ok visible ptrace_img matches"
    else fail "ptrace_img SSIM below threshold ($ss)"; fi
fi
if [ -s /app/scene_color.pfm ]; then
    ss=$(comp pfm /app/scene_color.pfm "$GOLD/ref.pfm")
    echo "scene_color SSIM vs golden: $ss"
    if python3 -c "print(1 if float('$ss')>=0.90 else 0)" | grep -q 1; then
        echo "ok scene_color matches"
    else fail "scene_color below threshold ($ss)"; fi
fi
if [ -s /app/scene_depth.pgm ]; then
    ss=$(comp pgm /app/scene_depth.pgm "$GOLD/ref.pgm")
    echo "scene_depth SSIM vs golden: $ss"
    if python3 -c "print(1 if float('$ss')>=0.85 else 0)" | grep -q 1; then
        echo "ok scene_depth matches"
    else fail "scene_depth below threshold ($ss)"; fi
fi

# ---- reproduce the color/depth renders via the recorded interpreter (independence) --
if [ -x "$PY" ] && [ -f /app/render_scene.py ] && [ -s /app/scene_color.pfm ] && [ -s /app/scene_depth.pgm ]; then
    "$PY" /app/render_scene.py /app/scene.cfg "$TMP/recolor.pfm" "$TMP/redepth.pgm" >/dev/null 2>&1
    if [ -s "$TMP/recolor.pfm" ] && [ -s "$TMP/redepth.pgm" ]; then
        ss=$(comp pfm "$TMP/recolor.pfm" "$GOLD/ref.pfm")
        echo "re-run scene_color SSIM: $ss"
        if python3 -c "print(1 if float('$ss')>=0.90 else 0)" | grep -q 1; then echo "ok reproduced color via interpreter"
        else fail "re-run scene_color mismatch ($ss)"; fi
        ssd=$(comp pgm "$TMP/redepth.pgm" "$GOLD/ref.pgm")
        if python3 -c "print(1 if float('$ssd')>=0.85 else 0)" | grep -q 1; then echo "ok reproduced depth via interpreter"
        else fail "re-run scene_depth mismatch ($ssd)"; fi
    else fail "recorded interpreter could not re-render scene"; fi
fi

# ---- C4: OSMesa headless GL smoke ---------------------------------------------
if [ ! -x /app/osmesa_check ]; then fail "osmesa_check not present/executable";
else
    if /app/osmesa_check "$TMP/osppd.ppm" >/dev/null 2>&1 && [ -s "$TMP/osppd.ppm" ]; then
        r=$(python3 - "$TMP/osppd.ppm" <<'PY'
from PIL import Image
import numpy as np,sys
im=Image.open(sys.argv[1]).convert('RGB')
a=np.asarray(im)
w,h=im.size
distinct=(len(np.unique(a.reshape(-1,3),axis=0)))
print('%d %d %d'%(w,h,distinct))
PY
)
        echo "osmesa render: $r"
        w=$(echo "$r"|awk '{print $1}'); h=$(echo "$r"|awk '{print $2}'); d=$(echo "$r"|awk '{print $3}')
        if [ "$w" = "96" ] && [ "$h" = "54" ] && [ "$d" -gt 1 ]; then echo "ok OSMesa headless GL rendered"
        else fail "OSMesa smoke output wrong ($r)"; fi
    else fail "osmesa_check did not produce output"; fi
fi

# ---------- hidden cases (executes-deliverable generalization) ------------------
HD=0; HT=0
for case in /tests/hidden/*/; do
    [ -d "$case" ] || continue
    cfg="$case/scene.cfg"
    [ -f "$cfg" ] || continue
    HT=$((HT+1))
    mkdir -p "$TMP/$(basename "$case")" "$TMP/$(basename "$case")/d"
    d="$TMP/$(basename "$case")"
    # golden
    python3 "$REF" "$cfg" "$d/ref.pfm" "$d/ref.pgm"
    # run the agent's path tracer on the hidden scene
    if [ -f "$TMP/ptrace_build" ] && "$TMP/ptrace_build" "$cfg" "$d/got.pfm" >/dev/null 2>&1 && [ -s "$d/got.pfm" ]; then
        ss=$(comp pfm "$d/got.pfm" "$d/ref.pfm")
        if python3 -c "print(1 if float('$ss')>=0.90 else 0)" | grep -q 1; then HD=$((HD+1)); echo "hidden $(basename "$case") ptrace SSIM=$ss OK"
        else echo "hidden $(basename "$case") ptrace SSIM=$ss <0.90"; fi
    else
        echo "hidden $(basename "$case") ptrace not rendered";
    fi
    # also exercise the offscreen rasterizer's depth path on the hidden scene
    if [ -x "$PY" ] && [ -f /app/render_scene.py ]; then
        "$PY" /app/render_scene.py "$cfg" "$d/hc.pfm" "$d/hd.pgm" >/dev/null 2>&1
        if [ -s "$d/hd.pgm" ]; then
            ssd=$(comp pgm "$d/hd.pgm" "$d/ref.pgm")
            if python3 -c "print(1 if float('$ssd')>=0.85 else 0)" | grep -q 1; then echo "hidden $(basename "$case") depth SSIM=$ssd OK"
            else echo "hidden $(basename "$case") depth SSIM=$ssd <0.85"; fi
        fi
    fi
done
if [ "$HT" -eq 0 ]; then fail "no hidden cases found";
elif [ "$HD" -lt "$HT" ]; then fail "hidden case coverage HD=$HD/$HT"; else echo "ok hidden: $HD/$HT"; fi

# ---- reward ---------------------------------------------------------------
if [ "$ALL_PASS" = "1" ]; then REWARD=1; else REWARD=0; fi
mkdir -p /logs/verifier
echo "$REWARD" > "$REWARD_FILE"
echo "REWARD=$REWARD"
exit 0