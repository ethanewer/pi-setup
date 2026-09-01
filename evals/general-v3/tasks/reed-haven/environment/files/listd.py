#!/usr/bin/env python3
"""listd -- Reedhaven Naturalist Society mailing-list manager.

Deterministic list-manager daemon. Reads a TOML config, applies a command
stream to the configured lists, and writes a JSON report. No network, no
clock, no randomness: the same config + stream always yields the same output.

Usage:
    python3 listd.py --config CONFIG_PATH --stream STREAM_PATH --out OUT_PATH

Config schema (TOML):

    [site]
    domain = "example.org"        # optional
    owner  = "postmaster@..."     # optional

    [[list]]
    name        = "list-name"     # required, unique
    members     = ["a@x", ...]    # optional, default []
    moderators  = ["m@x", ...]    # optional, default []
    open        = true            # optional, default true (false => closed)
    max_members = 128             # optional, default 128 (cap on members only)

Address normalization: surrounding whitespace is stripped; a display-name
form ``Name <addr>`` is reduced to the angle-bracket address; the result is
lowercased. Duplicates collapse at load time (first occurrence wins).
Moderator-only addresses are NOT members.

Command stream (one command per non-empty line; tokens are whitespace-split):

    subscribe <list> <addr>
        unknown-list | closed | duplicate | full | ok   (in this check order)
        ok appends the normalized addr to the list's members.
    unsubscribe <list> <addr>
        unknown-list | not-member | ok   (ok removes a member; moderator-only
        addresses are not members, so unsubscribing them yields not-member)
    post <list> <sender>
        unknown-list | accepted | rejected
        accepted iff the normalized sender is a member or a moderator of the
        list (regardless of open/closed); otherwise rejected.

Any other command word, or a wrong number of arguments, yields result
"malformed" (never fatal).

Exit codes: 0 on success; 2 if the config path is missing/unreadable or the
TOML is invalid (nothing is written to --out in that case).
"""

import argparse
import json
import sys

try:
    import tomllib
except ImportError:  # pragma: no cover
    tomllib = None


def norm(addr):
    a = str(addr).strip()
    if "<" in a and ">" in a and a.rfind(">") > a.rfind("<"):
        a = a[a.rfind("<") + 1:a.rfind(">")].strip()
    return a.lower()


def load_config(path):
    if tomllib is None:
        raise RuntimeError("tomllib unavailable")
    with open(path, "rb") as fh:
        data = tomllib.load(fh)
    lists = {}
    for entry in data.get("list", []):
        name = str(entry["name"])
        if name in lists:
            raise ValueError("duplicate list name: %s" % name)
        members, seen = [], set()
        for m in entry.get("members", []):
            n = norm(m)
            if n and n not in seen:
                seen.add(n)
                members.append(n)
        mods, mseen = [], set()
        for m in entry.get("moderators", []):
            n = norm(m)
            if n and n not in mseen:
                mseen.add(n)
                mods.append(n)
        lists[name] = {
            "members": members,
            "moderators": mods,
            "open": bool(entry.get("open", True)),
            "max_members": int(entry.get("max_members", 128)),
        }
    site = data.get("site", {})
    return site, lists


def process(site, lists, stream_path):
    actions = []
    with open(stream_path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if not line.strip():
                continue
            parts = line.split()
            cmd = parts[0]
            result = "malformed"
            if cmd == "subscribe" and len(parts) == 3:
                lname, addr = parts[1], norm(parts[2])
                lst = lists.get(lname)
                if lst is None:
                    result = "unknown-list"
                elif not lst["open"]:
                    result = "closed"
                elif addr in lst["members"]:
                    result = "duplicate"
                elif len(lst["members"]) >= lst["max_members"]:
                    result = "full"
                else:
                    lst["members"].append(addr)
                    result = "ok"
            elif cmd == "unsubscribe" and len(parts) == 3:
                lname, addr = parts[1], norm(parts[2])
                lst = lists.get(lname)
                if lst is None:
                    result = "unknown-list"
                elif addr not in lst["members"]:
                    result = "not-member"
                else:
                    lst["members"].remove(addr)
                    result = "ok"
            elif cmd == "post" and len(parts) == 3:
                lname, sender = parts[1], norm(parts[2])
                lst = lists.get(lname)
                if lst is None:
                    result = "unknown-list"
                elif sender in lst["members"] or sender in lst["moderators"]:
                    result = "accepted"
                else:
                    result = "rejected"
            actions.append({"cmd": line, "result": result})
    return actions


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--config", required=True)
    ap.add_argument("--stream", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    try:
        site, lists = load_config(args.config)
    except Exception as exc:
        print("listd: cannot load config %s: %s" % (args.config, exc), file=sys.stderr)
        sys.exit(2)

    actions = process(site, lists, args.stream)
    report = {
        "site": {"domain": site.get("domain"), "owner": site.get("owner")},
        "actions": actions,
        "rosters": {name: sorted(v["members"]) for name, v in lists.items()},
    }
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2, sort_keys=True)
        fh.write("\n")


if __name__ == "__main__":
    main()
