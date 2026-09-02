#!/bin/bash
#
# bryony-keep oracle. Does the real work: writes the provisioning tool, runs
# it on the visible spec fixture to declare the lists in the canonical
# config, then saves the manager's report to /app/report.json. Never reads
# /tests.
set -euo pipefail

cat > /app/configure_lists.py <<'PY'
#!/usr/bin/env python3
"""Bryony Keep list provisioning: read a spec JSON, declare its lists in the
canonical config /etc/keepmsg/lists.conf (replacement semantics, lowercase
folding, dedup, union merge), or reject an invalid spec without touching the
canonical config."""
import json
import os
import sys

CANONICAL = "/etc/keepmsg/lists.conf"


def fail(msg, code=2):
    sys.stderr.write("configure_lists: %s\n" % msg)
    sys.exit(code)


def fold(a):
    return str(a).strip().lower()


def load_spec(path):
    try:
        with open(path, encoding="utf-8") as fh:
            spec = json.load(fh)
    except Exception as exc:
        fail("cannot read spec %s (%s)" % (path, exc))
    if not isinstance(spec, dict):
        fail("spec must be a JSON object")
    domain = fold(spec.get("domain", ""))
    if not domain or "." not in domain:
        fail("spec has no usable domain")
    lists = spec.get("lists")
    if not isinstance(lists, list):
        fail("spec.lists must be a list")
    merged = {}
    for entry in lists:
        if not isinstance(entry, dict):
            fail("list entries must be objects")
        raw_addr = str(entry.get("address", ""))
        addr = fold(raw_addr)
        members = entry.get("members", [])
        if not isinstance(members, list):
            fail("members must be a list for %r" % raw_addr)
        if addr.count("@") != 1 or not addr.endswith("@" + domain):
            fail("list address %r is not within domain %r" % (raw_addr, domain))
        ms = set()
        for m in members:
            tok = fold(m)
            if not tok or tok.count("@") < 1:
                fail("invalid member %r for list %r" % (m, raw_addr))
            ms.add(tok)
        merged.setdefault(addr, set()).update(ms)
    return merged


def main():
    if len(sys.argv) != 2:
        fail("usage: configure_lists.py <spec.json>")
    merged = load_spec(sys.argv[1])

    lines = [
        "# Bryony Keep announcement lists -- managed by configure_lists.py",
        "# canonical path: %s" % CANONICAL,
        "",
    ]
    for addr in sorted(merged):
        lines.append("[%s]" % addr)
        lines.append("members = %s" % ", ".join(sorted(merged[addr])))
        lines.append("")
    os.makedirs(os.path.dirname(CANONICAL), exist_ok=True)
    with open(CANONICAL, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))
    sys.exit(0)


if __name__ == "__main__":
    main()
PY
chmod +x /app/configure_lists.py

python3 /app/configure_lists.py /app/spec/spec.json

python3 /opt/keepmsg/notimgr.py read > /app/report.json

echo "bryony-keep oracle complete"
ls -l /app/configure_lists.py /app/report.json
exit 0
