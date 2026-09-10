#!/usr/bin/env python3
"""Independent live-state verifier for the reeve-gate task.

Usage: check_state.py <scenario.json>

Reads the live /etc/passwd, /etc/shadow, /etc/group and the filesystem paths,
and asserts they match the scenario exactly. Prints one "ok:" / "MISMATCH:"
line per assertion. Exit code 0 iff every assertion holds.

Expected end state is derived from the scenario itself: the semantics of the
schema are fixed, so the required on-disk state is a pure function of the
scenario. The check is intentionally independent of the deliverable: it never
executes /app/setup_accounts.sh and never reads /opt/reeve-gate snapshot data.
"""
import datetime
import grp
import json
import os
import pwd
import stat
import sys
import warnings

import crypt

warnings.filterwarnings("ignore", category=DeprecationWarning)

PRISTINE = "/opt/reeve-gate/pristine/etc"


def epoch_days(date_s: str) -> int:
    y, m, d = (int(x) for x in date_s.split("-"))
    return (datetime.date(y, m, d) - datetime.date(1970, 1, 1)).days


def load_db(path: str):
    out = {}
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line:
                continue
            f = line.split(":")
            out[f[0]] = f
    return out


def main() -> int:
    scenario = json.load(open(sys.argv[1]))
    problems = []

    def ok(msg):
        print("ok:", msg)

    def bad(msg):
        problems.append(msg)
        print("MISMATCH:", msg)

    passwd = load_db("/etc/passwd")
    shadow = load_db("/etc/shadow")
    group = load_db("/etc/group")

    # ---- groups ----
    for g in scenario.get("groups", []):
        name = g["name"]
        if name not in group:
            bad(f"group {name} is missing from /etc/group")
            continue
        if group[name][2] != str(g["gid"]):
            bad(f"group {name} has gid {group[name][2]}, expected {g['gid']}")

    # ---- users ----
    for u in scenario.get("users", []):
        name = u["name"]
        if name not in passwd:
            bad(f"user {name} is missing from /etc/passwd")
            continue
        pf = passwd[name]
        if pf[2] != str(u["uid"]):
            bad(f"user {name} has uid {pf[2]}, expected {u['uid']}")
        if u["primary_group"] not in group:
            bad(f"user {name} primary group {u['primary_group']} is missing")
        elif pf[3] != group[u["primary_group"]][2]:
            bad(f"user {name} primary gid is {pf[3]}, "
                f"expected {group[u['primary_group']][2]} for {u['primary_group']}")
        if pf[4] != u.get("gecos", ""):
            bad(f"user {name} gecos is {pf[4]!r}, expected {u.get('gecos', '')!r}")
        if pf[5] != u["home"]:
            bad(f"user {name} home is {pf[5]}, expected {u['home']}")
        if pf[6] != u["shell"]:
            bad(f"user {name} shell is {pf[6]}, expected {u['shell']}")

        if name not in shadow:
            bad(f"user {name} is missing from /etc/shadow")
            continue
        sf = shadow[name]
        h = sf[1]
        locked = h.startswith("!")
        if u.get("locked") is True and not locked:
            bad(f"user {name} password is not locked")
        if u.get("locked") is False and locked:
            bad(f"user {name} password is locked, expected it to be usable")
        pw = u.get("password")
        if pw:
            hh = h[1:] if locked else h
            if not hh.startswith("$6$"):
                bad(f"user {name} password hash is not SHA-512")
            elif crypt.crypt(pw, hh) != hh:
                bad(f"user {name} password hash does not verify against scenario password")
        elif h.startswith("$"):
            bad(f"user {name} has an enabled password, but the scenario specifies none")

        # /etc/shadow columns (0-indexed): 0 name, 1 hash, 2 lastchange,
        # 3 min_days, 4 max_days, 5 warn_days, 6 inactive_days, 7 expiry
        for key, idx in (("min_days", 3), ("max_days", 4),
                         ("warn_days", 5), ("inactive_days", 6)):
            if u.get(key) is not None:
                if sf[idx] != str(u[key]):
                    bad(f"user {name} {key} (shadow field {idx}) is {sf[idx]!r}, "
                        f"expected {u[key]}")
        if u.get("expiry"):
            exp = epoch_days(u["expiry"])
            if sf[7] != str(exp):
                bad(f"user {name} account expiry is {sf[7]!r}, expected {exp}")

        for gn in u.get("supplementary_groups", []):
            if gn not in group:
                bad(f"supplementary group {gn} of {name} is missing")
                continue
            members = [m for m in group[gn][3].split(",") if m]
            if name not in members:
                bad(f"user {name} is not a member of supplementary group {gn}")

        if u.get("create_home"):
            home = u["home"]
            try:
                st = os.stat(home)
            except OSError:
                bad(f"home {home} of {name} does not exist")
                continue
            if u.get("home_mode"):
                mode = "%04o" % (st.st_mode & 0o777)
                if mode != u["home_mode"]:
                    bad(f"home {home} mode is {mode}, expected {u['home_mode']}")
            owner = pwd.getpwuid(st.st_uid).pw_name
            gname = grp.getgrgid(st.st_gid).gr_name
            if owner != name:
                bad(f"home {home} owner is {owner}, expected {name}")
            if gname != u["primary_group"]:
                bad(f"home {home} group is {gname}, expected {u['primary_group']}")
            else:
                ok(f"home {home} owner/mode ok")

    # ---- filesystem paths ----
    for p in scenario.get("paths", []):
        path = p["path"]
        try:
            st = os.lstat(path)
        except OSError:
            bad(f"path {path} does not exist")
            continue
        if p["kind"] == "directory" and not stat.S_ISDIR(st.st_mode):
            bad(f"path {path} is not a directory")
            continue
        mode = "%04o" % (st.st_mode & 0o777)
        if mode != p["mode"]:
            bad(f"path {path} mode is {mode}, expected {p['mode']}")
        owner = pwd.getpwuid(st.st_uid).pw_name
        gname = grp.getgrgid(st.st_gid).gr_name
        if owner != p["owner"]:
            bad(f"path {path} owner is {owner}, expected {p['owner']}")
        if gname != p["group"]:
            bad(f"path {path} group is {gname}, expected {p['group']}")
        m = p.get("marker")
        if m:
            mp = os.path.join(path, m["file"])
            try:
                data = open(mp, "rb").read()
                mst = os.lstat(mp)
            except OSError:
                bad(f"marker {mp} does not exist")
                continue
            if data != m["content"].encode():
                bad(f"marker {mp} content is {data!r}, expected {m['content']!r}")
            mmod = "%04o" % (mst.st_mode & 0o777)
            if mmod != m.get("mode", mmod):
                bad(f"marker {mp} mode is {mmod}, expected {m.get('mode')}")
            mowner = pwd.getpwuid(mst.st_uid).pw_name
            mgroup = grp.getgrgid(mst.st_gid).gr_name
            if mowner != m.get("owner", p["owner"]):
                bad(f"marker {mp} owner is {mowner}, expected {m.get('owner', p['owner'])}")
            if mgroup != m.get("group", p["group"]):
                bad(f"marker {mp} group is {mgroup}, expected {m.get('group', p['group'])}")
        else:
            ok(f"path {path} ok")

    # ---- exact account set: pristine set + exactly the scenario's entities ----
    pristine_passwd = load_db(os.path.join(PRISTINE, "passwd"))
    exp_users = set(pristine_passwd) | {u["name"] for u in scenario.get("users", [])}
    cur_users = set(passwd)
    if cur_users != exp_users:
        bad("users in /etc/passwd are not pristine+scenario: "
            + ",".join(sorted(cur_users ^ exp_users)))
    pristine_group = load_db(os.path.join(PRISTINE, "group"))
    exp_groups = set(pristine_group) | {g["name"] for g in scenario.get("groups", [])}
    cur_groups = set(group)
    if cur_groups != exp_groups:
        bad("groups in /etc/group are not pristine+scenario: "
            + ",".join(sorted(cur_groups ^ exp_groups)))

    if problems:
        print(f"FAIL: {len(problems)} mismatches")
        for p in problems[:20]:
            print("  -", p)
        return 1
    print("PASS: live system state matches the scenario")
    return 0


if __name__ == "__main__":
    sys.exit(main())