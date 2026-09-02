#!/usr/bin/env python3
"""Forensic recovery of intact `records` rows from a truncated SQLite file."""
import json, shutil, struct

SRC = '/app/ledger.db'
DST = '/app/copy.db'
shutil.copyfile(SRC, DST)  # work from a copy; keep original pristine

def varint(b, pos):
    r = 0
    while pos < len(b):
        x = b[pos]; pos += 1
        r = (r << 7) | (x & 0x7f)
        if not (x & 0x80):
            break
    return r, pos

def u16(b, o):
    return struct.unpack('>H', b[o:o+2])[0]

def decode_record(payload):
    try:
        hsz, q = varint(payload, 0)
    except Exception:
        return None
    serials = []; k = q
    while k < hsz:
        try:
            s, k = varint(payload, k)
        except Exception:
            return None
        serials.append(s)
    cols = []; d = hsz
    for st in serials:
        try:
            if st == 0:
                cols.append(None)
            elif st == 1:
                cols.append(payload[d]); d += 1
            elif st == 2:
                cols.append(u16(payload, d)); d += 2
            elif st == 3:
                cols.append(int.from_bytes(payload[d:d+3], 'big')); d += 3
            elif st == 4:
                cols.append(int.from_bytes(payload[d:d+4], 'big')); d += 4
            elif st == 5:
                cols.append(int.from_bytes(payload[d:d+6], 'big')); d += 6
            elif st == 6:
                cols.append(int.from_bytes(payload[d:d+8], 'big')); d += 8
            elif st == 7:
                cols.append(struct.unpack('>d', payload[d:d+8])[0]); d += 8
            elif st == 8:
                cols.append(0)
            elif st == 9:
                cols.append(1)
            elif st >= 13 and st % 2 == 1:
                n = (st - 13) // 2
                cols.append(payload[d:d+n].decode('utf-8', 'replace')); d += n
            else:
                return None
        except Exception:
            return None
    return cols

def recover(path):
    bs = open(path, 'rb').read()
    ps = struct.unpack('>H', bs[16:18])[0]
    if ps == 1:
        ps = 65536
    nphys = len(bs) // ps
    records = {}
    for pgno in range(1, nphys + 1):
        pg = bs[(pgno-1)*ps:pgno*ps]
        hd = 100 if pgno == 1 else 0
        typ = pg[hd] & 0x0f
        if typ == 0x0d:
            ncell = u16(pg, hd + 3)
            ca = hd + 8
            for i in range(ncell):
                co = u16(pg, ca + 2*i)
                if co < 0 or co >= ps:
                    continue
                try:
                    C, q = varint(pg, co)
                    rowid, q = varint(pg, q)
                except Exception:
                    continue
                if q + C > ps:
                    continue
                cols = decode_record(pg[q:q+C])
                if cols and len(cols) >= 3 and isinstance(cols[1], str) \
                        and cols[1].startswith('tag') and isinstance(cols[2], (int, float)):
                    records[rowid] = {'id': rowid, 'tag': cols[1], 'amount': float(cols[2])}
    return records

records = recover(DST)
rows = [records[i] for i in sorted(records)]
json.dump({'recovered_rows': rows}, open('/app/recovered.json', 'w'), indent=2)
print('recovered', len(rows), 'rows', rows[0]['id'], '..', rows[-1]['id'])