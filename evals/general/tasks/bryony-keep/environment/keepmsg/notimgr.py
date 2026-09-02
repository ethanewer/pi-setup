#!/usr/bin/env python3
"""notimgr -- the Bryony Keep announcement-list manager control tool.

The manager (an offline reader here) honors ONLY the canonical config path:

    /etc/keepmsg/lists.conf

A config file placed at any other path is ignored by design. Subcommands:

  read    parse the canonical config and print a JSON description
  check   exit 0 iff the canonical config exists and parses

Config grammar (case-insensitive on addresses and member addresses):

  # comments and blank lines are ignored
  [<list address>]
  members = <comma-separated member addresses>

Semantics implemented by `read`:
  - addresses are folded to lowercase; a list appears at most once;
  - members are folded to lowercase, deduplicated, and sorted;
  - an empty `members` value means the list has zero members;
  - when the same list address appears in more than one section, the member
    sets are merged (union).
"""
import configparser
import json
import sys

CANONICAL = "/etc/keepmsg/lists.conf"


def parse(path):
    cp = configparser.ConfigParser(interpolation=None, strict=False)
    cp.optionxform = str
    with open(path, encoding="utf-8") as fh:
        cp.read_file(fh)
    merged = {}
    for section in cp.sections():
        addr = section.strip().lower()
        raw = cp.get(section, "members", fallback="")
        members = [m.strip().lower() for m in raw.split(",") if m.strip()]
        merged.setdefault(addr, set()).update(members)
    return [{"address": a, "members": sorted(merged[a])} for a in sorted(merged)]


def main(argv):
    if len(argv) != 2 or argv[1] not in ("read", "check"):
        sys.stderr.write("usage: notimgr.py read|check\n")
        return 2
    try:
        lists = parse(CANONICAL)
    except OSError as exc:
        if argv[1] == "check":
            return 1
        sys.stderr.write("notimgr: canonical config unreadable: %s\n" % exc)
        return 1
    except configparser.Error as exc:
        if argv[1] == "check":
            return 1
        sys.stderr.write("notimgr: canonical config unparseable: %s\n" % exc)
        return 1
    if argv[1] == "read":
        print(json.dumps({"config": CANONICAL, "lists": lists}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
