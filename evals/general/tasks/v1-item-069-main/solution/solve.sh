#!/bin/bash
set -euo pipefail

mkdir -p /app/recovered

python3 - <<'PY'
import struct, os, json

def varint(b, off):
    v = 0
    for i in range(9):
        x = b[off]; off += 1
        if i == 8:
            v = (v << 8) | x; break
        v = (v << 7) | (x & 0x7f)
        if not (x & 0x80): break
    return v, off

def serial_value(b, cpos, typ):
    if typ == 1: v = b[cpos]; cpos += 1
    elif typ == 2: v = int.from_bytes(b[cpos:cpos+2], 'big', signed=True); cpos += 2
    elif typ == 3: v = int.from_bytes(b'\x00'+b[cpos:cpos+3], 'big', signed=True); cpos += 4
    elif typ == 4: v = int.from_bytes(b[cpos:cpos+4], 'big', signed=True); cpos += 4
    elif typ == 5: v = int.from_bytes(b'\x00\x00\x00\x00'+b[cpos:cpos+6], 'big', signed=True); cpos += 6
    elif typ == 6: v = int.from_bytes(b'\x00'+b[cpos:cpos+7], 'big', signed=True); cpos += 7
    elif typ == 7: v = struct.unpack('>d', b[cpos:cpos+8])[0]; cpos += 8
    elif typ == 8: v = None
    elif typ == 9: v = True
    elif typ == 10: v = False
    elif typ == 11: v = None
    else:
        n = (typ - 12)//2 if typ % 2 == 0 else (typ - 13)//2
        raw = b[cpos:cpos+n]; cpos += n
        v = raw.decode('utf-8') if typ % 2 else raw
    return v, cpos

path = '/app/data/corrupt.db'
f = open(path,'rb'); hdr = f.read(100)
pgsz = struct.unpack('>H', hdr[16:18])[0]
if pgsz == 1: pgsz = 65536
fsize = os.path.getsize(path)
f.close()

def read_page(n):
    if n < 1 or (n-1)*pgsz >= fsize: return None
    f = open(path,'rb'); f.seek((n-1)*pgsz); d = f.read(pgsz); f.close()
    if n == 1: d = d[::-1] if False else d[100:]
    return d

def decode_leaf_ids(data):
    """Return row ids stored in a table leaf page."""
    ids = []
    nc = int.from_bytes(data[3:5], 'big')
    for i in range(nc):
        s = 8+2*i
        if s+2 > len(data): break
        off = int.from_bytes(data[s:s+2], 'big')   # full-page offset
        o = off
        if o < 0 or o+1 >= len(data): continue
        rsize, o = varint(data, o); rid, o = varint(data, o)
        if o + rsize > len(data): continue
        ids.append(rid)
    return ids

def decode_master_rows(data):
    rows = []
    nc = int.from_bytes(data[3:5], 'big')
    for i in range(nc):
        s = 8+2*i
        if s+2 > len(data): break
        off = int.from_bytes(data[s:s+2], 'big')
        o = off - 100
        if o < 0 or o+1 >= len(data): continue
        rsize, o = varint(data, o)          # record size
        rid, o = varint(data, o)
        if o + rsize > len(data): continue
        pl = data[o:o+rsize]
        hs, hp = varint(pl, 0)
        ser=[]; pos=hp
        while pos < hs and pos < len(pl):
            t,pos=varint(pl,pos); ser.append(t)
        cpos=hs; vals=[]
        for t in ser:
            v,cpos=serial_value(pl,cpos,t); vals.append(v)
        rows.append(vals)
    return rows

# page 1 is sqlite_master; find emp root page
master_data = read_page(1)
root = None
for vals in decode_master_rows(master_data):
    if len(vals) >= 4 and (vals[1] == b'emp' or vals[1] == 'emp'):
        root = vals[3]
if root is None:
    raise SystemExit('emp root page not found')

recovered = []
seen = set()
def walk(n):
    if n in seen: return
    seen.add(n)
    data = read_page(n)
    if data is None: return
    typ = data[0]
    nc = int.from_bytes(data[3:5], 'big')
    start = 12 if typ in (2,5) else 8
    offs = []
    for i in range(nc):
        s = start + 2*i
        if s+2 > len(data): break
        offs.append(int.from_bytes(data[s:s+2], 'big'))
    if typ in (2,5):
        first = int.from_bytes(data[8:12], 'big')
        walk(first)
        for off in offs:
            if off <= len(data)-4:
                walk(int.from_bytes(data[off:off+4], 'big'))
    elif typ == 13:
        recovered.extend(decode_leaf_ids(data))

walk(root)
recovered_ids = sorted(set(recovered))
with open('/app/recovered/recovered.json','w') as f:
    json.dump({"recovered": recovered_ids, "count": len(recovered_ids)}, f, indent=2)
print("recovered rows:", len(recovered_ids), "range", recovered_ids[0] if recovered_ids else None, recovered_ids[-1] if recovered_ids else None)
PY