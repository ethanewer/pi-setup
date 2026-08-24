#!/bin/bash
set -euo pipefail

cat > /app/args.py <<'EOF'
import json, sys

def parse(args):
    mode=None; count=None; label=None; farg=None
    i=0
    n=len(args)
    def split_eq(a):
        if a.startswith("--") and "=" in a:
            k,v=a.split("=",1)
            return k,v
        return a,None
    while i<n:
        a,v = split_eq(args[i])
        if a=="--mode":
            if v is None:
                if i+1>=n: raise SystemExit(2)
                v=args[i+1]; i+=1
            mode=v
        elif a=="-m":
            if v is None:
                if i+1>=n: raise SystemExit(2)
                mode=args[i+1]; i+=1
            else: mode=v
        elif a in ("--count","-c"):
            if v is None:
                if i+1>=n: raise SystemExit(2)
                v=args[i+1]; i+=1
            count=int(v)
        elif a=="--label":
            if v is None:
                if i+1>=n: raise SystemExit(2)
                label=args[i+1]; i+=1
            else: label=v
        elif a.startswith("-"):
            raise SystemExit(2)
        else:
            if farg is None: farg=a
        i+=1
    if mode is None or farg is None or count is None:
        raise SystemExit(2)
    return {"mode":mode,"count":count,"label":label if label is not None else "","file":farg}

out=parse(sys.argv[1:])
json.dump(out, open("/app/parsed.json","w"))
EOF

python3 /app/args.py --mode fast -c 7 --label=two words /tmp/file1.txt