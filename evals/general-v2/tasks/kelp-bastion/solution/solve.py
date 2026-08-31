"""Oracle / reference solver for kelp-bastion.

Usage: python3 solve.py <db_file> <output_json>

Reads a possibly byte-truncated SQLite database containing the `ledger`
table, walks the table B-tree directly in the raw bytes, salvages every
row stored on pages that are wholly present, and writes a diagnosis +
salvaged rows to the output JSON.
"""
import json
import struct
import sys


def read_varint(buf, off):
    """SQLite big-endian varint: 1-9 bytes."""
    result = 0
    for i in range(9):
        b = buf[off + i]
        if i == 8:
            result = (result << 8) | b
            return result, off + 9
        result = (result << 7) | (b & 0x7F)
        if not (b & 0x80):
            return result, off + i + 1
    raise ValueError("unreachable varint")


def to_signed64(v):
    v &= (1 << 64) - 1
    if v >= (1 << 63):
        v -= 1 << 64
    return v


INT_SIZES = {1: 1, 2: 2, 3: 3, 4: 4, 5: 6, 6: 8}


def decode_record(payload):
    """Decode a SQLite record into a list of python values."""
    hdr_len, p = read_varint(payload, 0)
    serials = []
    while p < hdr_len:
        st, p = read_varint(payload, p)
        serials.append(st)
    vals = []
    body = hdr_len
    for st in serials:
        if st == 0:
            vals.append(None)
        elif st in INT_SIZES:
            n = INT_SIZES[st]
            vals.append(int.from_bytes(payload[body:body + n], "big", signed=True))
            body += n
        elif st == 7:
            vals.append(struct.unpack(">d", payload[body:body + 8])[0])
            body += 8
        elif st == 8:
            vals.append(0)
        elif st == 9:
            vals.append(1)
        elif st >= 13 and st % 2 == 1:
            n = (st - 13) // 2
            vals.append(payload[body:body + n].decode("utf-8"))
            body += n
        elif st >= 12 and st % 2 == 0:
            n = (st - 12) // 2
            vals.append(bytes(payload[body:body + n]))
            body += n
        else:
            raise ValueError("unsupported serial type %d" % st)
    return vals


def parse_page(data, pgno, page_size, reserved):
    """Parse one b-tree page. Returns ('interior', children) or ('leaf', rows)."""
    base = (pgno - 1) * page_size
    hdr = base + (100 if pgno == 1 else 0)
    ptype = data[hdr]
    ncells = int.from_bytes(data[hdr + 3:hdr + 5], "big")
    usable = page_size - reserved
    if ptype == 5:  # interior table page
        right = int.from_bytes(data[hdr + 8:hdr + 12], "big")
        ptrs = hdr + 12
        children = []
        for i in range(ncells):
            cp = int.from_bytes(data[ptrs + 2 * i:ptrs + 2 * i + 2], "big")
            child = int.from_bytes(data[base + cp:base + cp + 4], "big")
            children.append(child)
        children.append(right)
        return "interior", children
    if ptype == 13:  # leaf table page
        ptrs = hdr + 8
        rows = []
        for i in range(ncells):
            cp = int.from_bytes(data[ptrs + 2 * i:ptrs + 2 * i + 2], "big")
            cell = base + cp
            payload_len, cell = read_varint(data, cell)
            rowid, cell = read_varint(data, cell)
            if payload_len > usable - 35:
                raise ValueError("overflow payload not supported")
            payload = data[cell:cell + payload_len]
            rows.append((to_signed64(rowid), payload))
        return "leaf", rows
    raise ValueError("unsupported page type %d on page %d" % (ptype, pgno))


def main():
    db_path, out_path = sys.argv[1], sys.argv[2]
    with open(db_path, "rb") as fh:
        data = fh.read()

    if len(data) < 100 or data[:16] != b"SQLite format 3\x00":
        raise ValueError("not a SQLite database file")

    page_size = int.from_bytes(data[16:18], "big")
    if page_size == 1:
        page_size = 65536
    reserved = data[20]
    declared_pages = int.from_bytes(data[28:32], "big")
    present_pages = len(data) // page_size
    truncated = len(data) < declared_pages * page_size
    mode = "truncated" if truncated else "intact"

    # Locate the root page of `ledger` in sqlite_master (page 1).
    kind, payload = parse_page(data, 1, page_size, reserved)
    root = None
    if kind == "leaf":
        for _rowid, rec in payload:
            vals = decode_record(rec)
            # sqlite_master columns: type, name, tbl_name, rootpage, sql
            if len(vals) >= 4 and vals[0] == "table" and vals[1] == "ledger":
                root = vals[3]
    else:
        raise ValueError("sqlite_master spread over interior pages; unsupported")

    # Walk the ledger b-tree; only pages wholly present in the file count.
    salvaged = []
    if root is not None:
        stack = [root]
        seen = set()
        while stack:
            pg = stack.pop()
            if pg in seen or pg < 1 or pg > present_pages:
                continue  # page absent / truncated away -> lost
            seen.add(pg)
            kind, payload = parse_page(data, pg, page_size, reserved)
            if kind == "interior":
                stack.extend(payload)
            else:
                for rowid, rec in payload:
                    vals = decode_record(rec)
                    # id INTEGER PRIMARY KEY is stored as NULL; rowid is the id.
                    _id_col, account, posted_on, amount, memo = vals
                    salvaged.append({
                        "id": rowid,
                        "account": account,
                        "posted_on": posted_on,
                        "amount": round(float(amount), 6),
                        "memo": memo,
                    })

    salvaged.sort(key=lambda r: r["id"])
    result = {
        "mode": mode,
        "page_size": page_size,
        "declared_pages": declared_pages,
        "present_pages": present_pages,
        "lost_pages": max(0, declared_pages - present_pages),
        "salvaged_rows": salvaged,
    }
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=2, sort_keys=True)
        fh.write("\n")


if __name__ == "__main__":
    main()
