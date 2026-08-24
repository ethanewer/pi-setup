#!/bin/bash
set -euo pipefail

# Oracle for item-065-main: implement the shard packer/unpacker, ship a bundle
# of /app/source, and demonstrate a byte-exact round trip.

cat > /app/c4shards.py <<'PYEOF'
import base64, gzip, json, os

def _is_utf8_text(data):
    try:
        data.decode("utf-8")
        return b"\x00" not in data
    except (UnicodeDecodeError, ValueError):
        return False

def pack(root, bundle_out, limit=4096):
    root=os.path.abspath(root); dirs=[]; files=[]; total=0
    for base, subdirs, names in os.walk(root):
        base_rel=os.path.relpath(base,root)
        if base_rel!=".": dirs.append(base_rel.replace(os.sep,"/"))
        for name in sorted(names):
            rel = (name if base_rel=="." else base_rel.replace(os.sep,"/")+"/"+name)
            full=os.path.join(base,name); files.append((rel,full))
    dirs.sort(); files.sort(key=lambda x:x[0])
    os.makedirs(bundle_out, exist_ok=True)
    recs=[{"type":"dir","path":d} for d in dirs]
    for rel,full in files:
        data=open(full,"rb").read()
        if _is_utf8_text(data):
            recs.append({"type":"file","path":rel,"size":len(data),"text":data.decode("utf-8")})
        else:
            recs.append({"type":"blob","path":rel,"size":len(data),"base64":base64.b64encode(data).decode("ascii")})
    def key(r):
        p=r["path"]; return p+"/" if r["type"]=="dir" else p
    recs.sort(key=key)
    shards=[]; cur=[]; cb=0
    for r in recs:
        nb=len(json.dumps(r,ensure_ascii=False).encode("utf-8"))+1
        if cur and cb+nb>limit:
            shards.append(cur); cur=[]; cb=0
        cur.append(r); cb+=nb
    if cur: shards.append(cur)
    names=[]
    for i,ch in enumerate(shards):
        fn="shard-%05d.jsonl.gz"%i
        payload="".join(json.dumps(r,ensure_ascii=False)+"\n" for r in ch).encode("utf-8")
        open(os.path.join(bundle_out,fn),"wb").write(gzip.compress(payload))
        names.append(fn)
    json.dump({"type":"c4-shard-bundle","version":1,"shards":names,"records":len(recs),"compression":"gzip"}, open(os.path.join(bundle_out,"meta.json"),"w"), indent=2)

def unpack(bundle_in, dest):
    meta=json.load(open(os.path.join(bundle_in,"meta.json")))
    os.makedirs(dest, exist_ok=True)
    for fn in meta["shards"]:
        raw=gzip.decompress(open(os.path.join(bundle_in,fn),"rb").read()).decode("utf-8")
        for line in raw.splitlines():
            if not line.strip(): continue
            r=json.loads(line); full=os.path.join(dest,*r["path"].split("/"))
            if r["type"]=="dir": os.makedirs(full,exist_ok=True)
            elif r["type"]=="file":
                os.makedirs(os.path.dirname(full),exist_ok=True)
                open(full,"w",encoding="utf-8",newline="").write(r["text"])
            elif r["type"]=="blob":
                os.makedirs(os.path.dirname(full),exist_ok=True)
                open(full,"wb").write(base64.b64decode(r["base64"]))

def main(argv=None):
    import argparse, sys
    argv = argv if argv is not None else sys.argv[1:]
    ap = argparse.ArgumentParser(prog="c4shards")
    sub = ap.add_subparsers(dest="command", required=True)
    p = sub.add_parser("pack")
    p.add_argument("root")
    p.add_argument("bundle_out")
    p.add_argument("--limit", type=int, default=4096)
    u = sub.add_parser("unpack")
    u.add_argument("bundle_in")
    u.add_argument("dest")
    args = ap.parse_args(argv)
    if args.command == "pack":
        pack(args.root, args.bundle_out, args.limit)
    else:
        unpack(args.bundle_in, args.dest)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

PYEOF

python3 /app/make_tree.py /app/source
rm -rf /app/bundle_shards /app/restored
python3 /app/c4shards.py pack /app/source /app/bundle_shards --limit 256
python3 /app/c4shards.py unpack /app/bundle_shards /app/restored

python3 - <<'CHK'
import os

def cmp_trees(a, b):
    sa, sb = set(), set()
    for base, dirs, files in os.walk(a):
        rel = os.path.relpath(base, a)
        for d in dirs:
            sa.add("/" + (os.path.join(rel, d) if rel != "." else d).replace(os.sep, "/"))
        for f in files:
            rr = (os.path.join(rel, f) if rel != "." else f).replace(os.sep, "/")
            sa.add("/" + rr)
    for base, dirs, files in os.walk(b):
        rel = os.path.relpath(base, b)
        for d in dirs:
            sb.add("/" + (os.path.join(rel, d) if rel != "." else d).replace(os.sep, "/"))
        for f in files:
            rr = (os.path.join(rel, f) if rel != "." else f).replace(os.sep, "/")
            sb.add("/" + rr)
    if sa != sb:
        return False
    for base, dirs, files in os.walk(a):
        rel = os.path.relpath(base, a)
        for f in files:
            rr = (os.path.join(rel, f) if rel != "." else f)
            if open(os.path.join(a, rr), "rb").read() != open(os.path.join(b, rr), "rb").read():
                return False
    return True

ok = cmp_trees("/app/source", "/app/restored")
assert ok, "round trip mismatch"
print("oracle self-check passed: byte-exact round trip ok")
CHK
