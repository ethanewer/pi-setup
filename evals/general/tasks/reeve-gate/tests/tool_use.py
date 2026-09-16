#!/usr/bin/env python3
"""Runtime enforcement: are account-DB writes made only by the built tools?

Reads one strace log (the deliverable run traced with
`strace -f -e trace=open,openat,creat,rename,renameat,renameat2,unlink,unlinkat`)
and reports every open-for-write, creat, rename or unlink touching the
account databases (/etc/passwd, /etc/shadow, /etc/group, /etc/gshadow — and
the shadow tools' `+`, `-`, `.lock`, `.<pid>` write variants) that was NOT
performed by a shadow tool built from the pinned upstream source.

Exit 0 iff no violation. Prints one readable line per violation.
"""
import re
import sys

DB = {"/etc/passwd", "/etc/shadow", "/etc/group", "/etc/gshadow"}

ALLOWED_EXE = {
    "useradd", "userdel", "usermod",
    "groupadd", "groupdel", "groupmod", "groupmems",
    "chage", "chfn", "chsh", "chpasswd", "chgpasswd", "expiry", "gpasswd",
    "grpck", "grpconv", "grpunconv", "lastlog", "login", "logoutd",
    "newgrp", "newusers", "nologin", "passwd", "pwck", "pwconv", "pwunconv",
    "sg", "su", "vigr", "vipw",
}

DB_SUFFIX = re.compile(r"(?:[+\-]|\.lock|\.[0-9]+)$")
WRITE_FLAGS = ("O_WRONLY", "O_RDWR", "O_CREAT", "O_TRUNC", "O_APPEND")


def db_form(path: str):
    """Return base DB path if `path` names a DB (or a write variant) else None."""
    if path in DB:
        return path
    stripped = DB_SUFFIX.sub("", path)
    return stripped if stripped in DB else None


def parse(log: str) -> list[str]:
    exe_of = {}
    parent = {}
    violations = []

    execve_re = re.compile(r"^(\d+)\s+execve\(\"([^\"]+)\"")
    fork_re = re.compile(r"^(\d+)\s+(?:clone|fork|vfork)\([^)]*(?:child_tidptr=[^)]*= (\d+)|= (\d+))\)")
    plain_fork_re = re.compile(r"^(\d+)\s+(?:fork|vfork)\(\)\s+= (\d+)")

    def exe_name(pid: int) -> str:
        seen = set()
        p = pid
        while p not in seen:
            seen.add(p)
            if p in exe_of:
                return exe_of[p]
            p = parent.get(p, -1)
            if p == -1:
                return "?"
        return "?"

    for line in log.splitlines():
        line = line.strip()
        if not line:
            continue
        m = execve_re.match(line)
        if m:
            pid = int(m.group(1))
            if " = -1" in line or " = ?" in line:
                continue
            exe_of[pid] = m.group(2).rsplit("/", 1)[-1]
            continue
        m = fork_re.match(line)
        if m:
            child = m.group(1)
            if line.rstrip().endswith("= -1"):
                continue
            if child:
                parent[int(child)] = int(m.group(0).split()[0])
        else:
            m = plain_fork_re.match(line)
            if m:
                pid = int(m.group(1))
                child = int(m.group(2))
                parent[child] = pid
                continue
        if m:
            continue

        m = re.match(r"^(\d+)\s+(\w+)\(([^)]*)", line)
        if not m:
            continue
        pid = int(m.group(1))
        call = m.group(2)
        args = m.group(3)
        if call == "execve":
            continue

        if call == "creat":
            pm = re.search(r'"([^"]*)"', args)
            if not pm:
                continue
            path = pm.group(1)
            is_write = True
        elif call.startswith("open"):
            pm = re.search(r'"([^"]*)"', args)
            if not pm:
                continue
            path = pm.group(1)
            after = args.split('"', 2)[2] if args.count('"') > 1 else ""
            is_write = any(f in after for f in WRITE_FLAGS)
        elif call.startswith("rename") or call.startswith("unlink"):
            paths = re.findall(r'"([^"]*)"', args)
            path = None
            for p in paths:
                if p.startswith("/etc/"):
                    path = p
                    break
            if path is None:
                continue
            is_write = db_form(path) is not None
        else:
            continue

        if not is_write or not path:
            continue
        if db_form(path) is None:
            continue
        exe = exe_name(pid)
        if exe in ALLOWED_EXE:
            continue
        violations.append(
            f"{call} {path} by pid {pid} / exe {exe or '?'} — "
            "account DBs may only be written by the built shadow tools"
        )
    return violations


def main(argv) -> int:
    if len(argv) < 2:
        print("usage: tool_use.py <strace.log>", file=sys.stderr)
        return 2
    try:
        log = open(argv[1], encoding="utf-8", errors="replace").read()
    except OSError as e:
        print(f"cannot read trace {argv[1]}: {e}", file=sys.stderr)
        return 2
    if "execve(" not in log:
        print("strace produced no execve events; is strace installed/permitted?", file=sys.stderr)
        return 2
    violations = parse(log)
    unique = dict.fromkeys(violations)
    for v in unique:
        print("DB-WRITE-VIOLATION:", v)
    if unique:
        print(f"FAIL: {len(unique)} account-DB write(s) by a process that is not a built tool")
        return 1
    print("ok: every account-DB write was performed by the built toolchain")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))