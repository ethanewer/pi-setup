#!/bin/bash
# Oracle for onyx-frame: author the compact splash renderer (the deliverable
# program), then RUN it on the shipped visible spec to produce the frame and
# the self-size report. Never reads /tests.
set -eu

# ---- 1. Write the deliverable renderer. Compact by design: the bootloader
# caps gzip(source) at 400 bytes and raw source at 750 bytes.
cat > /app/splash.py <<'PY'
import gzip,json,sys
a=sys.argv
s=json.load(open(a[1] if len(a)>1 else"/app/spec.json"))
R=s["ramp"];w=s["width"];h=s["height"];m=s["mod"];d=s["den"]
f=lambda y,x:(s["kx"]*x*x+s["ky"]*y+s["kxy"]*(x*y%m))//d%len(R)
o="\n".join("".join(R[f(y,x)]for x in range(w))for y in range(h))+"\n"
open(a[2] if len(a)>2 else"/app/splash.txt","w").write(o)
b=open(__file__,"rb").read()
r={"raw_bytes":len(b),"gzip_bytes":len(gzip.compress(b)),"gzip_max":s["gzip_max"],"raw_max":s["raw_max"],"width":w,"height":h}
json.dump(r,open(a[3] if len(a)>3 else"/app/frame-report.json","w"))
PY
chmod +x /app/splash.py

# ---- 2. Run the renderer on the shipped visible spec.
python3 /app/splash.py /app/spec.json /app/splash.txt /app/frame-report.json

echo "solve.sh done -> /app/splash.py /app/splash.txt /app/frame-report.json"
wc -c /app/splash.py /app/splash.txt /app/frame-report.json
