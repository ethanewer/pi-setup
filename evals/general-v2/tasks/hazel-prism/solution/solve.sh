#!/bin/bash
# Oracle for hazel-prism: write the compact algorithmic renderer (the real
# work — it must fit the raw + gzip source caps with no embedded pixels), then
# measure it to produce the sizes report. Never reads /tests.
set -eu
mkdir -p /app

cat > /app/frame.py <<'PY'
import sys
R=" .:-=+*#%@"
m="mandel";n=[]
for t in sys.argv[1:]:
 if t in("mandel","julia"):m=t
 else:n.append(int(t))
a,b=(34,92) if m=="mandel" else(36,84)
rows,cols=(n+[a,b])[:2]
def f(c,r):
 if m=="mandel":
  z=0j;k=0;cr=-2.1+3.0*c/(cols-1);ci=-1.2+2.4*r/(rows-1)
  while k<40 and abs(z)<=2.0:z=z*z+complex(cr,ci);k+=1
 else:
  zr=-1.5+3.0*c/(cols-1);zi=-1.5+3.0*r/(rows-1);k=0
  while k<40 and zr*zr+zi*zi<=4.0:zr,zi=zr*zr-zi*zi-0.7,2*zr*zi+0.27015;k+=1
 return R[min(k*9//40,9)]
print("\n".join("".join(f(c,r)for c in range(cols))for r in range(rows)))
PY

chmod +x /app/frame.py

python3 - <<'PY'
import gzip, json
src = open("/app/frame.py", "rb").read()
report = {"source_bytes": len(src), "gzip_bytes": len(gzip.compress(src, 9))}
with open("/app/frame-sizes.json", "w") as fh:
    json.dump(report, fh)
print("frame.py:", report)
assert report["source_bytes"] <= 900, "raw cap"
assert report["gzip_bytes"] <= 480, "gzip cap"
PY

# smoke: both default frames render to the documented dimensions
python3 /app/frame.py | awk 'NR==1{print "mandel cols:", length($0)} END{print "mandel rows:", NR}'
python3 /app/frame.py julia | awk 'NR==1{print "julia cols:", length($0)} END{print "julia rows:", NR}'

echo "solve.sh done"
