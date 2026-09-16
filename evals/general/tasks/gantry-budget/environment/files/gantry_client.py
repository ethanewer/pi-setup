#!/usr/bin/env python3
"""gantry_client -- the vended, billed summarisation API for the gantry
deployment.

This module is part of the platform, not of any one job. The agent's batch
job imports it and drives it; the platform's ledger is the only record the
deployment trusts for billing. Do not edit it in a job run.

Model contract
--------------

A "prompt" is a text block (or several blocks) the job sends to the model.
Each block begins with a record header line::

    ### RECORD <id>

followed by zero or more labelled field lines::

    ::TITLE:: <title text>
    ::AMOUNT:: <amount text>
    ::DEADLINE:: <date text>
    ::IMPACT:: <impact sentence>

Extra lines (notes, context, excerpts) may appear anywhere inside a block;
they are ignored by the model but are still billed. The labelled lines are
optional -- a block with no ::TITLE:: line simply returns title=None.

For each block the model returns one summary object with the keys
id / title / amount / deadline / impact. Field values are the text to the
right of the label on its own line, verbatim. A missing label yields
None for that key.

Billing
-------

  * one token == one whitespace-separated word in the text (``len(text.split())``)
  * every request (API call) carries a fixed overhead of
    ``REQUEST_OVERHEAD_TOKENS`` tokens regardless of size
  * output is billed at the token count of the JSON serialisation of the
    summary objects returned

Every request is appended to the ledger as one JSON line::

    {"request": n, "ids": [...], "prompt": "...",
     "in_tokens": int, "out_tokens": int}

The ledger file is chosen from the ``BILLING_LEDGER_PATH`` environment
variable, or defaults to ``/tmp/gantry_ledger.jsonl``. The ledger is opened
in append mode; a fresh ledger path yields a fresh bill.
"""
import json
import os
import re

REQUEST_OVERHEAD_TOKENS = 150

_ID_LINE = re.compile(r'^###\s+RECORD\s+(\S+)\s*$', re.M)
_LABEL_LINE = re.compile(r'^::(TITLE|AMOUNT|DEADLINE|IMPACT)::\s*(.*)$')


def count_tokens(text):
    """Number of billed tokens in *text* (whitespace-separated words)."""
    return len(text.split())


def _split_blocks(prompt):
    """Split a prompt into per-record text blocks, preserving order."""
    starts = [m.start() for m in _ID_LINE.finditer(prompt)]
    if not starts:
        return []
    blocks = []
    ids = []
    for i, start in enumerate(starts):
        end = starts[i + 1] if i + 1 < len(starts) else len(prompt)
        blocks.append(prompt[start:end])
        ids.append(_ID_LINE.match(prompt[start:end]).group(1))
    return list(zip(blocks, ids))


class GantryClient:
    def __init__(self, ledger_path=None):
        if ledger_path is None:
            ledger_path = os.environ.get("BILLING_LEDGER_PATH",
                                         "/tmp/gantry_ledger.jsonl")
        self.ledger_path = ledger_path
        os.makedirs(os.path.dirname(os.path.abspath(ledger_path)),
                    exist_ok=True)
        self._req = 0

    # -- request path -------------------------------------------------------
    def summarize(self, block_text):
        """One record in one request. Returns the summary dict or None."""
        out = self.summarize_many([block_text])
        return out[0] if out else None

    def summarize_many(self, blocks):
        """Send *blocks* as a single request. Returns a list of summary
        dicts in block order; blocks without a record header are dropped."""
        prompt = "\n\n".join(b.strip("\n") for b in blocks if b.strip())
        entries = _split_blocks(prompt)
        if not entries:
            return []
        responses = []
        for block, rid in entries:
            fields = {}
            for line in block.splitlines():
                m = _LABEL_LINE.match(line)
                if m:
                    fields[m.group(1)] = m.group(2)
            responses.append({
                "id": rid,
                "title": fields.get("TITLE"),
                "amount": fields.get("AMOUNT"),
                "deadline": fields.get("DEADLINE"),
                "impact": fields.get("IMPACT"),
            })
        line = {
            "request": self._req,
            "ids": [r["id"] for r in responses],
            "prompt": prompt,
            "in_tokens": REQUEST_OVERHEAD_TOKENS + count_tokens(prompt),
            "out_tokens": sum(count_tokens(json.dumps(r, sort_keys=True))
                              for r in responses),
        }
        with open(self.ledger_path, "a") as fh:
            fh.write(json.dumps(line) + "\n")
        self._req += 1
        return responses


if __name__ == "__main__":
    print("gantry_client: vendored billed summarisation API (see source)")