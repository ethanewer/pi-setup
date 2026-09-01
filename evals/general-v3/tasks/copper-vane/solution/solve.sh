#!/bin/bash
# Oracle for copper-vane: write the salvage program, then RUN it on the visible
# fixture to produce /app/salvaged.json. Never reads /tests.
set -eu

SOLVER="/app/salvage.py"
OUT="/app/salvaged.json"

cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""Salvage intact rows from a truncated SQLite database (byte-level walk)."""
import json
import struct
import sys


def read_varint(buf, i):
    """SQLite big-endian varint. Returns (value, next_index)."""
    result = 0
    for _ in range(8):
        b = buf[i]
        i += 1
        result = (result << 7) | (b & 0x7F)
        if not (b & 0x80):
            return result, i
    result = (result << 8) | buf[i]
    return result, i + 1


def u16be(buf, off):
    return (buf[off] << 8) | buf[off + 1]


def u32be(buf, off):
    return int.from_bytes(buf[off:off + 4], "big")


def decode_serial(payload, pos, st):
    if st == 0:
        return None, pos
    if st in (1, 2, 3, 4, 5, 6):
        n = {1: 1, 2: 2, 3: 3, 4: 4, 5: 6, 6: 8}[st]
        return int.from_bytes(payload[pos:pos + n], "big", signed=True), pos + n
    if st == 7:
        return struct.unpack(">d", payload[pos:pos + 8])[0], pos + 8
    if st == 8:
        return 0, pos
    if st == 9:
        return 1, pos
    if st >= 13 and st % 2 == 1:
        n = (st - 13) // 2
        return payload[pos:pos + n].decode("utf-8"), pos + n
    raise ValueError("unsupported serial type %d" % st)


def decode_record(payload):
    header_size, i = read_varint(payload, 0)
    serials = []
    while i < header_size:
        st, i = read_varint(payload, i)
        serials.append(st)
    vals = []
    pos = header_size
    for st in serials:
        v, pos = decode_serial(payload, pos, st)
        vals.append(v)
    return vals


def page_bytes(data, page_size, page_no):
    start = (page_no - 1) * page_size
    if start >= len(data):
        return None
    return data[start:start + page_size]


def find_manifest_root(data, page_size):
    """Walk page 1 (sqlite_schema) to find the rootpage of table 'manifest'."""
    page = page_bytes(data, page_size, 1)
    if page is None or page[100] != 0x0D:
        return None
    ncells = u16be(page, 103)
    for c in range(ncells):
        cell_off = u16be(page, 108 + 2 * c)
        try:
            plen, i = read_varint(page, cell_off)
            rowid, i = read_varint(page, i)
            vals = decode_record(page[i:i + plen])
            typ, name, _tbl, rootpage, _sql = vals[:5]
            if typ == "table" and name == "manifest":
                return rootpage
        except Exception:
            continue
    return None


def salvage_manifest_page(data, page_size, root_page):
    """Walk the manifest root (leaf table page 0x0D); keep rows whose payload
    lies wholly within the retained bytes."""
    page = page_bytes(data, page_size, root_page)
    if page is None:
        return []
    hdr = 100 if root_page == 1 else 0
    if page[hdr] != 0x0D:
        return []
    ncells = u16be(page, hdr + 3)
    ptr_base = hdr + 8
    rows = []
    for c in range(ncells):
        cell_off = u16be(page, ptr_base + 2 * c)
        try:
            plen, i = read_varint(page, cell_off)
            rowid, i = read_varint(page, i)
            abs_end = (root_page - 1) * page_size + i + plen
            if abs_end > len(data):
                continue  # payload runs past the truncation cut -> lost row
            crate, origin, weighed_on, mass = decode_record(page[i:i + plen])[:4]
            rows.append({
                "id": rowid,
                "crate": crate,
                "origin": origin,
                "weighed_on": weighed_on,
                "mass": mass,
            })
        except Exception:
            continue
    rows.sort(key=lambda r: r["id"])
    return rows


def salvage(data):
    retained = len(data)
    page_size = 0
    if retained >= 18:
        ps_raw = u16be(data, 16)
        page_size = 65536 if ps_raw == 1 else ps_raw
    declared_pages = u32be(data, 28) if retained >= 32 else 0
    retained_pages = retained // page_size if page_size else 0

    if page_size and declared_pages and retained >= declared_pages * page_size:
        mode = "intact"
    elif retained < 100:
        mode = "empty"
    elif page_size and retained % page_size == 0:
        mode = "page-aligned-truncation"
    else:
        mode = "mid-page-truncation"

    rows = []
    if retained >= 108 and page_size:
        root = find_manifest_root(data, page_size)
        if root:
            rows = salvage_manifest_page(data, page_size, root)

    diagnosis = {
        "mode": mode,
        "page_size": page_size,
        "declared_pages": declared_pages,
        "retained_pages": retained_pages,
        "intact_rows": len(rows),
    }
    return {"diagnosis": diagnosis, "salvaged": rows}


def main():
    db_path, out_path = sys.argv[1], sys.argv[2]
    with open(db_path, "rb") as fh:
        data = fh.read()
    result = salvage(data)
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=2)


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

# Run the produced program on the visible fixture to create the deliverable.
python3 "$SOLVER" /app/manifest.db /app/salvaged.json

echo "solve.sh done -> $SOLVER and /app/salvaged.json"
ls -l "$SOLVER" "$OUT"
