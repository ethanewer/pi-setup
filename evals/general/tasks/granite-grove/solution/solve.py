#!/usr/bin/env python3
"""Granite Grove pipeline.

For a given case directory this script:
  1. calendar  - fetches each requested person's fresh .ics from the live
                 schedule service (with the auth token) and stores them in
                 <case>/out/<key>.ics
  2. overlaps  - drives the provided find_overlaps.py tool over the case
                 availability.csv and stores the JSON at <case>/out/overlaps.json
  3. transfer  - implements the validate+transfer rule (debit buyer, credit
                 seller, reassign item owner, append log) writing
                 <case>/out/transfer_out.json

Usage:
  python3 /app/solve.py --case <dir> [--url <service-http://host:port>] \
      [--out <result.json>]
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
import urllib.request
import time

HERE = os.path.dirname(os.path.realpath(__file__))
TOOLS = os.path.join(HERE, "tools")


def http_get(url, token, timeout=10):
    req = urllib.request.Request(url, headers={"X-Auth-Token": token})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        if r.status != 200:
            raise RuntimeError(f"HTTP {r.status} from {url}")
        return r.read().decode("utf-8")


def ensure_service(case):
    """Spawn a local schedule service for the case and return its base URL."""
    cfg_path = os.path.join(case, "calendar", "service_config.json")
    with open(cfg_path) as fh:
        cfg = json.load(fh)
    record = tempfile.mkdtemp(prefix="grv_")
    proc = subprocess.Popen(
        [sys.executable, os.path.join(TOOLS, "schedule_service.py"),
         "--config", cfg_path, "--port", str(cfg.get("port", 0)),
         "--outdir", record],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    port = None
    deadline = time.time() + 15
    while time.time() < deadline:
        line = proc.stdout.readline()
        if "GRANITE_GROVE_UP" in line:
            port = int(line.split("port=")[1].split()[0])
            break
    if port is None:
        raise RuntimeError("service did not come up")
    return f"http://127.0.0.1:{port}", proc


def fetch_calendars(case, url, token):
    with open(os.path.join(case, "calendar", "service_config.json")) as fh:
        cfg = json.load(fh)
    people = [p["key"] for p in cfg["people"]]
    out = os.path.join(case, "out")
    os.makedirs(out, exist_ok=True)
    for key in people:
        body = http_get(f"{url}/person/{key}.ics", token)
        with open(os.path.join(out, f"{key}.ics"), "w") as fh:
            fh.write(body)
    return [f"{k}.ics" for k in people]


def drive_overlaps(case, outdir):
    avail = os.path.join(case, "availability", "availability.csv")
    result = subprocess.run([sys.executable, os.path.join(TOOLS, "find_overlaps.py"),
                             avail], capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"find_overlaps failed: {result.stderr}")
    data = json.loads(result.stdout)
    os.makedirs(outdir, exist_ok=True)
    with open(os.path.join(outdir, "overlaps.json"), "w") as fh:
        json.dump(data, fh, indent=2)
    return data


def run_transfer(case):
    base = os.path.join(case, "ledger")
    with open(os.path.join(base, "ledger.json")) as fh:
        ledger = json.load(fh)          # {"parties": {key: {"label","balance"}}}
    with open(os.path.join(base, "items.json")) as fh:
        items = json.load(fh)           # {id: {"name","owner","price"}}
    with open(os.path.join(base, "transfer.json")) as fh:
        tfr = json.load(fh)             # {"item","seller","buyer","amount"}
    with open(os.path.join(base, "transfer_log.json")) as fh:
        log = json.load(fh)

    parties = ledger["parties"]
    buyer, seller, item, amount = tfr["buyer"], tfr["seller"], tfr["item"], tfr["amount"]

    approved = True
    reason = None
    if buyer == seller:
        approved, reason = False, "buyer and seller are the same party"
    elif buyer not in parties:
        approved, reason = False, "buyer is not a known party"
    elif seller not in parties:
        approved, reason = False, "seller is not a known party"
    elif item not in items:
        approved, reason = False, "item does not exist"
    elif items[item]["owner"] != seller:
        approved, reason = False, "seller does not own the item"
    elif amount <= 0:
        approved, reason = False, "amount must be positive"
    elif parties[buyer]["balance"] < amount:
        approved, reason = False, "buyer has insufficient funds"

    if approved:
        parties[buyer]["balance"] -= amount
        parties[seller]["balance"] += amount
        items[item]["owner"] = buyer
        log.append({"item": item, "from": seller, "to": buyer,
                    "amount": amount})

    balances = {k: v["balance"] for k, v in parties.items()}
    result = {
        "approved": approved,
        "reason": reason,
        "balances": balances,
        "items": {k: {"name": v["name"], "owner": v["owner"],
                      "price": v["price"]} for k, v in items.items()},
        "log": log,
    }
    return result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--case", required=True)
    ap.add_argument("--url", default=None)
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    case = os.path.abspath(args.case)
    outdir = os.path.join(case, "out")
    os.makedirs(outdir, exist_ok=True)

    with open(os.path.join(case, "calendar", "service_config.json")) as fh:
        cfg = json.load(fh)
    service = args.url
    proc = None
    if service is None:
        service, proc = ensure_service(case)
        time.sleep(0.5)
    try:
        fetched = fetch_calendars(case, service, cfg["auth_token"])
        overlaps = drive_overlaps(case, outdir)
    finally:
        if proc is not None:
            proc.terminate()

    transfer = run_transfer(case)
    with open(os.path.join(outdir, "transfer_out.json"), "w") as fh:
        json.dump(transfer, fh, indent=2)

    answer = {
        "pipeline": "granite-grove",
        "calendar": {"status": "ok", "files": fetched},
        "overlaps_count": len(overlaps),
        "transfer": {"status": "approved" if transfer["approved"] else "rejected",
                     "reason": transfer["reason"]},
    }
    out_path = args.out or os.path.join(case, "out", "answer.json")
    with open(out_path, "w") as fh:
        json.dump(answer, fh, indent=2)
    print(json.dumps(answer))


if __name__ == "__main__":
    main()