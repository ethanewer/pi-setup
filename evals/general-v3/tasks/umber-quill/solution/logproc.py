#!/usr/bin/env python3
import sys, os, json, re
from collections import OrderedDict

def parse_events(text):
    out=[]
    for raw in text.splitlines():
        if not raw.strip():
            continue
        try:
            obj=json.loads(raw)
        except Exception:
            continue
        if not all(k in obj for k in ("id","ts","severity","runner","value")):
            continue
        out.append((raw, obj))
    return out

def cmd_rounds(inp, out_dir):
    with open(inp) as f:
        text=f.read()
    ev=parse_events(text)
    groups=OrderedDict()
    for raw,obj in ev:
        groups.setdefault(obj["id"],[]).append((raw,obj))
    buckets={1:[],2:[],3:[]}
    for key in sorted(groups):
        recs=groups[key]
        recs=sorted(recs, key=lambda r: r[1]["ts"])  # stable sort by ts
        n=len(recs)
        third=n//3
        for i,(raw,obj) in enumerate(recs):
            if i < third:
                r=1
            elif i >= 2*third:
                r=3
            else:
                r=2
            buckets[r].append(raw)
    os.makedirs(out_dir, exist_ok=True)
    for r in (1,2,3):
        with open(os.path.join(out_dir,"round%d.out"%r),"w") as fo:
            fo.write("\n".join(buckets[r]))
            if buckets[r]:
                fo.write("\n")

def cmd_frames(inp, out):
    text=open(inp).read()
    traces=[]
    cur=None
    for line in text.splitlines():
        s=line.strip()
        if s.startswith("TRACE:"):
            cur=[s[len("TRACE:"):].strip(),[]]
            traces.append(cur)
        elif cur is not None and s.startswith("frame:"):
            cs=s[len("frame:"):].strip()
            if "::" in cs:
                cs=cs.split("::",1)[0].strip()
            cur[1].append(cs)
    with open(out,"w") as f:
        json.dump(traces, f, ensure_ascii=False)

IP_RE=re.compile(r'\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b')
DATE_RE=re.compile(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z')

def cmd_dates(inp, out):
    lines=open(inp).read().splitlines()
    rows=[]
    for idx,line in enumerate(lines,1):
        if IP_RE.search(line):
            ds=DATE_RE.findall(line)
            if ds:
                rows.append((idx, ds[-1]))
    with open(out,"w") as f:
        for i,d in rows:
            f.write("%d\t%s\n"% (i,d))

def main():
    args=sys.argv[1:]
    if len(args)>=1 and args[0]=="rounds":
        cmd_rounds(args[1], args[2])
    elif len(args)>=1 and args[0]=="frames":
        cmd_frames(args[1], args[2])
    elif len(args)>=1 and args[0]=="dates":
        cmd_dates(args[1], args[2])
    else:
        sys.stderr.write("usage: logproc.py rounds|frames|dates INPUT OUTPUT\n")
        sys.exit(2)

if __name__=="__main__":
    main()