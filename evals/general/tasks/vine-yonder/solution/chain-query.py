#!/usr/bin/env python3
"""chain-query.py -- query a live dev-mode node RPC for chain data.

Usage:
    python3 /app/chain-query.py [NODE_URL] [TARGET_ADDR]

Defaults: NODE_URL = http://127.0.0.1:9000/rpc and TARGET_ADDR is read from
/app/chain_target.txt. Pulls node status, the latest block, a transaction in
that block, and the account record, then writes /app/chain-account.json.
"""
import json
import os
import sys
import urllib.request

OUT = "/app/chain-account.json"
DEFAULT_NODE = "http://127.0.0.1:9000/rpc"


def get(base, path):
    with urllib.request.urlopen(base + path, timeout=30) as r:
        return json.load(r)


def main():
    base = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_NODE
    targets_argv = sys.argv[2] if len(sys.argv) > 2 else None
    if targets_argv:
        target = targets_argv
    else:
        with open("/app/chain_target.txt") as f:
            target = f.read().strip()
    base = base.rstrip("/")

    status = get(base, "/status")
    height = status["height"]
    block = get(base, "/block/latest")
    if str(block.get("number")) != str(height):
        block = get(base, "/block/%d" % height)
    tx = get(base, "/tx/%s" % block["txs"][0]["hash"])
    account = get(base, "/account/%s" % target)

    report = {
        "node": {
            "name": status["name"],
            "version": status.get("version"),
            "network": status.get("network"),
            "syncing": status.get("syncing"),
            "peers": status.get("peers"),
            "height": status.get("height"),
        },
        "block": {
            "number": block["number"],
            "hash": block["hash"],
            "prevHash": block.get("prevHash"),
            "timestamp": block.get("timestamp"),
            "txCount": block.get("txCount"),
        },
        "transaction": {
            "hash": tx["hash"],
            "from": tx.get("from"),
            "to": tx.get("to"),
            "amount": tx.get("amount"),
            "gasUsed": tx.get("gasUsed"),
            "blockNumber": tx.get("blockNumber"),
        },
        "account": {
            "address": account.get("address"),
            "balance": account.get("balance"),
            "nonce": account.get("nonce"),
        },
    }
    with open("/app/chain-account.json", "w") as f:
        json.dump(report, f, indent=1)
        f.write("\n")
    print(json.dumps(report))


if __name__ == "__main__":
    main()