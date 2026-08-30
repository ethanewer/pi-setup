#!/usr/bin/env python3
"""vine-yonder verifier helpers. Each subcommand exits non-zero on any failure."""
import json
import sys


def fail(msg):
    sys.stderr.write("VINE CHECK FAIL: %s\n" % msg)
    sys.exit(1)


def dataset_report(report_path, manifest_dir):
    import os
    import csv as _csv
    r = json.load(open(report_path))
    m = json.load(open(os.path.join(manifest_dir, "manifest.json")))
    cfg = m["required_config"]
    split = m["required_split"]
    field = m["field"]
    if r["config"] != cfg:
        fail("report.config=%s expected %s" % (r["config"], cfg))
    if r["split"] != split:
        fail("report.split=%s expected %s" % (r["split"], split))
    if r["field"] != field:
        fail("report.field=%s expected %s" % (r["field"], field))
    if r["name"] != m["dataset"]:
        fail("report.name != manifest.dataset")
    csv_path = os.path.join(manifest_dir, cfg, split + ".csv")
    rows, total = 0, 0.0
    col = None
    with open(csv_path) as f:
        rd = _csv.reader(f)
        for row in rd:
            if not row:
                continue
            cells = [c.strip() for c in row]
            if field in cells:
                col = cells.index(field)
                break
        for row in rd:
            if not row or col >= len(row):
                continue
            cell = (row[col] or "").strip()
            if cell == "":
                continue
            try:
                total += float(cell)
            except ValueError:
                continue
            rows += 1
    if int(r["rows"]) != rows:
        fail("rows=%s expected %d" % (r["rows"], rows))
    if abs(float(r["total"]) - total) > 1e-6:
        fail("total=%s expected %s" % (r["total"], total))
    print("dataset:%s cfg=%s split=%s total=%s rows=%s"
          % (m["dataset"], cfg, split, total, rows))


def chain_verify(report_path, chain_file, match_target):
    r = json.load(open(report_path))
    c = json.load(open(chain_file))
    st = c["node"]
    if r["node"]["name"] != st["name"]:
        fail("node.name")
    if r["node"]["network"] != st["network"]:
        fail("node.network")
    if int(r["node"]["height"]) != int(st["height"]):
        fail("node.height")
    if bool(r["node"]["syncing"]) != bool(st["syncing"]):
        fail("node.syncing")
    blk = c["blocks"][str(st["height"])]
    if int(r["block"]["number"]) != int(blk["number"]):
        fail("block.number")
    if r["block"]["hash"] != blk["hash"]:
        fail("block.hash")
    if r["block"]["prevHash"] != blk["prevHash"]:
        fail("block.prevHash")
    if int(r["block"]["txCount"]) != int(blk["txCount"]):
        fail("block.txCount")
    tx = blk["txs"][0]
    if r["transaction"]["hash"] != tx["hash"]:
        fail("tx.hash")
    if r["transaction"]["amount"] != tx["amount"]:
        fail("tx.amount")
    if int(r["transaction"]["blockNumber"]) != int(blk["number"]):
        fail("tx.blockNumber")
    acct = c["accounts"][match_target]
    if r["account"]["address"] != match_target:
        fail("account.address")
    if r["account"]["balance"] != acct["balance"]:
        fail("account.balance")
    if int(r["account"]["nonce"]) != int(acct["nonce"]):
        fail("account.nonce")
    print("chain ok node=%s network=%s height=%s target=%s" %
          (st["name"], st["network"], st["height"], match_target))


def monitor_check(log_path):
    lines = [ln for ln in open(log_path).read().splitlines() if ln.strip()]
    if len(lines) < 6:
        fail("monitor samples=%d <6" % len(lines))
    ts = []
    for ln in lines:
        parts = dict(kv.split("=", 1) for kv in ln.split() if "=" in kv)
        if "ts" not in parts or "metric" not in parts:
            fail("monitor line format")
        try:
            ts.append(int(parts["ts"]))
            int(parts["metric"])
        except ValueError:
            fail("monitor non-numeric field")
    span = ts[-1] - ts[0]
    if not (50 <= span <= 70):
        fail("monitor span=%d outside [50,70]" % span)
    for i in range(1, len(ts)):
        d = ts[i] - ts[i - 1]
        if not (7 <= d <= 13):
            fail("monitor interval=%d not ~10s" % d)
    print("monitor ok samples=%d span=%d" % (len(ts), span))


def spark_check(runtimes_file, logs_dir, evdir):
    import os
    found = {}
    for ln in open(runtimes_file).read().splitlines():
        parts = ln.split(",")
        if len(parts) != 3:
            fail("runtime line malformed: %s" % ln)
        mode, date, ms = parts
        if mode in ("LOCAL", "CLUSTER"):
            try:
                found[mode] = (date, int(ms))
            except ValueError:
                fail("runtime ms not int: %s" % ms)
    if "LOCAL" not in found or "CLUSTER" not in found:
        fail("runtimes.txt missing LOCAL and/or CLUSTER")
    dates = {f[: -len("_events.log")]
             for f in os.listdir(evdir) if f.endswith("_events.log")}
    if not dates:
        fail("no events files in %s" % evdir)
    for mode in ("LOCAL", "CLUSTER"):
        date, ms = found[mode]
        if ms <= 0:
            fail("%s elapsed must be >0" % mode)
        if date not in dates:
            fail("%s date=%s not attributed to an events file" % (mode, date))
        outf = os.path.join(logs_dir, "spark-%s.out" % mode.lower())
        if not os.path.exists(outf) or "DATE_SUMMARY" not in open(outf).read():
            fail("%s run logged no DATE_SUMMARY (job didn't complete)" % mode)
    print("spark ok local=%sms cluster=%sms"
          % (found["LOCAL"][1], found["CLUSTER"][1]))


def pipeline_check(out_path, pipe_dir):
    import os
    text = open(out_path).read()
    positions = [text.find(m) for m in ("STAGE1", "STAGE2", "STAGE3")]
    if any(p < 0 for p in positions) or positions != sorted(positions):
        fail("pipeline out missing/in-order STAGE1..3")
    for n in ("1", "2", "3"):
        if not os.path.isfile(os.path.join(pipe_dir, "generated",
                                           "stage%s.txt" % n)):
            fail("pipeline missing generated/stage%s.txt" % n)
    print("pipeline ok %s" % pipe_dir)


def main():
    cmd = sys.argv[1]
    args = sys.argv[2:]
    if cmd == "dataset":
        dataset_report(*args)
    elif cmd == "chain":
        chain_verify(*args)
    elif cmd == "monitor":
        monitor_check(*args)
    elif cmd == "spark":
        spark_check(*args)
    elif cmd == "pipeline":
        pipeline_check(*args)
    else:
        fail("unknown cmd " + cmd)


if __name__ == "__main__":
    main()