#!/usr/bin/env python3
"""patchdeck — the candle-works ledger's fix-request applier (do not modify).

Usage: python3 /app/tools/patchdeck.py apply [REQUESTS_DIR]

Reads every top-level ``*.json`` request file in REQUESTS_DIR (default
/app/requests) in sorted order.  Each processed request consumes exactly one
ATTEMPT; every attempt is appended as one JSON line to
/app/tools/patchdeck.log.  Processed request files are renamed to ``*.done``
so re-running cannot double-process them.

Request schema (all fields required):

    {"finding": "F-01",
     "file": "/app/lib/wickkit.py",
     "line": <audited 1-based line number>,
     "old": "<exact current text of that line>",
     "new": "<replacement single line>"}

A request is APPLIED only when the finding id, file, line number, and old
text all match the audit record AND the file's current line still equals the
audited excerpt; otherwise it is REJECTED (the attempt is still consumed).
The run's success check fails when the log holds more attempts than the
audit budget allows (one per finding), any REJECTED attempt, or any finding
that was never applied exactly once.
"""

import hashlib
import json
import os
import sys

AUDIT_PATH = "/app/audit/findings.json"
LOG_PATH = "/app/tools/patchdeck.log"


def sha256_text(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def apply_request(req, findings, attempt_no, req_name):
    entry = {"attempt": attempt_no, "request": req_name}
    fid = req.get("finding") if isinstance(req, dict) else None
    if not isinstance(fid, str) or fid not in findings:
        entry.update(result="REJECTED", reason="unknown finding")
        return entry
    finding = findings[fid]
    entry["finding"] = fid
    if req.get("file") != finding["file"]:
        entry.update(result="REJECTED", reason="file does not match the finding")
        return entry
    if req.get("line") != finding["line"]:
        entry.update(result="REJECTED", reason="line does not match the finding")
        return entry
    old = req.get("old")
    if not isinstance(old, str) or old != finding["excerpt"]:
        entry.update(result="REJECTED",
                     reason="old text does not match the audited excerpt")
        return entry
    new = req.get("new")
    if not isinstance(new, str) or not new or "\n" in new:
        entry.update(result="REJECTED", reason="new must be a non-empty single line")
        return entry
    path = finding["file"]
    with open(path, "r", encoding="utf-8") as fh:
        lines = fh.read().split("\n")
    idx = finding["line"] - 1
    if idx < 0 or idx >= len(lines) or lines[idx] != old:
        entry.update(result="REJECTED",
                     reason="current file line no longer matches the audited excerpt")
        return entry
    lines[idx] = new
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))
    entry.update(result="APPLIED", line=finding["line"],
                 sha_old=sha256_text(old), sha_new=sha256_text(new))
    return entry


def main(argv):
    if len(argv) < 2 or argv[1] != "apply":
        print(__doc__.strip(), file=sys.stderr)
        return 2
    req_dir = argv[2] if len(argv) > 2 else "/app/requests"
    with open(AUDIT_PATH, "r", encoding="utf-8") as fh:
        audit = json.load(fh)
    findings = {f["id"]: f for f in audit["findings"]}
    names = sorted(n for n in os.listdir(req_dir) if n.endswith(".json")) \
        if os.path.isdir(req_dir) else []
    attempt = 0
    os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
    with open(LOG_PATH, "a", encoding="utf-8") as log:
        for name in names:
            attempt += 1
            path = os.path.join(req_dir, name)
            try:
                with open(path, "r", encoding="utf-8") as fh:
                    req = json.load(fh)
                entry = apply_request(req, findings, attempt, name)
            except Exception as exc:
                entry = {"attempt": attempt, "request": name,
                         "result": "REJECTED", "reason": "unparseable request: %s" % exc}
            log.write(json.dumps(entry) + "\n")
            log.flush()
            print("patchdeck: %s" % json.dumps(entry))
            os.rename(path, path + ".done")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
