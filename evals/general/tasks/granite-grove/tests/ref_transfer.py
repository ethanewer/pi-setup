#!/usr/bin/env python3
"""Verifier-side reference implementation of the transfer rule.

Reads the same ledger inputs the agent's pipeline sees and computes the exact
state a correct validate-and-transfer must produce.  Used to diff the agent's
<case>/out/transfer_out.json.  Mirrors the contract documented in instruction.md.
"""
import json
import os
import sys


def main():
    base = sys.argv[1]  # ledger dir containing ledger.json, items.json,
                        # transfer.json, transfer_log.json
    ledger = json.load(open(os.path.join(base, "ledger.json")))
    items = json.load(open(os.path.join(base, "items.json")))
    tfr = json.load(open(os.path.join(base, "transfer.json")))
    log = json.load(open(os.path.join(base, "transfer_log.json")))

    parties = ledger["parties"]
    buyer, seller, item, amount = tfr["buyer"], tfr["seller"], tfr["item"], tfr["amount"]

    approved, reason = True, None
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
        log.append({"item": item, "from": seller, "to": buyer, "amount": amount})

    out = {
        "approved": approved,
        "reason": reason,
        "balances": {k: v["balance"] for k, v in parties.items()},
        "items": {k: {"name": v["name"], "owner": v["owner"],
                      "price": v["price"]} for k, v in items.items()},
        "log": log,
    }
    json.dump(out, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()