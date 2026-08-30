#!/usr/bin/env python3
"""Ridgeline tool 4 - parse fixed-width ledger records (40-byte blocks)."""

import os, sys, json

WIDTH = 40


def parse(data: bytes):
    recs = []
    na = nb = nt = nu = nm = 0
    tb = tl = net = 0
    for off in range(0, len(data), WIDTH):
        blk = data[off:off + WIDTH]
        if len(blk) < WIDTH:
            nm += 1
            recs.append({"type": "malformed", "offset": off})
            continue
        tag = blk[0:2]
        if tag == b"AC":
            r = {
                "type": "AC",
                "code": blk[2:10].decode().strip(),
                "holder": blk[10:24].decode().strip(),
                "balance": int(blk[24:40].strip()),
            }
            na += 1
            tb += r["balance"]
            recs.append(r)
        elif tag == b"BO":
            r = {
                "type": "BO",
                "code": blk[2:10].decode().strip(),
                "title": blk[10:26].decode().strip(),
                "pages": int(blk[26:40].strip()),
            }
            nb += 1
            tl += r["pages"]
            recs.append(r)
        elif tag == b"TX":
            r = {
                "type": "TX",
                "txn": blk[2:10].decode().strip(),
                "account": blk[10:18].decode().strip(),
                "kind": blk[18:26].decode().strip(),
                "amount": int(blk[26:39].strip()),
                "sign": blk[39:40].decode(),
            }
            nt += 1
            net += r["amount"] if r["sign"] == "+" else -r["amount"]
            recs.append(r)
        else:
            nu += 1
            recs.append({"type": "unknown", "offset": off})
    summary = {
        "n_account": na, "n_book": nb, "n_txn": nt,
        "n_unknown": nu, "n_malformed": nm,
        "total_balance": tb, "total_pages": tl, "net_amount": net,
    }
    return {"records": recs, "summary": summary}


def main(argv):
    if len(argv) != 3:
        print("usage: parse_fw.py <in.records> <out.json>")
        return 2
    with open(argv[1], "rb") as f:
        data = f.read()
    doc = parse(data)
    with open(argv[2], "w") as f:
        json.dump(doc, f, ensure_ascii=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))