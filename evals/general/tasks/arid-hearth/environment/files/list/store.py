#!/usr/bin/env python3
"""arid-hearth: minimal local mailing-list kernel.

This is the low-level, immutable list store for the benchmark. The agent
configures it (list.conf) and wraps it with automation (list_ops.sh); this
file must NOT be modified.

Membership model under the `open-confirm` policy:
  * subscribe   -> address goes to the PENDING set and a confirmation letter
                   (with a one-time token) is produced in the outbox.
  * confirm     -> only a matching token promotes a pending address to the
                   ACTIVE (member) set.
  * unsubscribe -> removes an address from both pending and active sets.
"""
import shutil
import uuid
import sys
import os

ROOT = "/app/list"
CONF = os.path.join(ROOT, "list.conf")
STATE = os.path.join(ROOT, "state")

VALID_POLICIES = ("open-confirm", "open-auto", "closed")


def load_config():
    policy = "unset"
    if os.path.exists(CONF):
        with open(CONF) as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = [x.strip() for x in line.split("=", 1)]
                if k == "policy":
                    policy = v
    return policy


def state_paths():
    members = os.path.join(STATE, "members.txt")
    pending = os.path.join(STATE, "pending.tsv")
    outbox = os.path.join(STATE, "outbox")
    for d in (STATE, outbox):
        os.makedirs(d, exist_ok=True)
    return members, pending, outbox


def read_rows(path):
    rows = []
    if os.path.exists(path):
        with open(path) as fh:
            for line in fh:
                line = line.rstrip("\n")
                if line:
                    rows.append(line.split("\t"))
    return rows


def write_rows(path, rows):
    with open(path, "w") as fh:
        for row in rows:
            fh.write("\t".join(row) + "\n")


def token_of(rows, addr):
    for row in rows:
        if len(row) >= 2 and row[0] == addr:
            return row[1]
    return None


def main():
    if len(sys.argv) < 2:
        sys.stderr.write("usage: %s <policy|reset|subscribe|confirm|unsubscribe|membership|pending> ...\n" % sys.argv[0])
        sys.exit(1)
    cmd = sys.argv[1]
    members, pending, outbox = state_paths()

    if cmd == "policy":
        print(load_config())
    elif cmd == "reset":
        for p in (members, pending):
            if os.path.exists(p):
                write_rows(p, [])
        for f in os.listdir(outbox):
            os.remove(os.path.join(outbox, f))
    elif cmd == "subscribe":
        addr = sys.argv[2] if len(sys.argv) > 2 else ""
        if not addr:
            sys.exit(2)
        pol = load_config()
        if pol != "open-confirm":
            sys.stderr.write("subscribe blocked: policy is %r, open-confirm required\n" % pol)
            sys.exit(3)
        tok = __import__("uuid").uuid4().hex[:12]
        pend = [r for r in read_rows(pending) if r[0] != addr]
        pend.append([addr, tok])
        write_rows(pending, pend)
        safe = addr.replace("@", "_at_").replace(" ", "_") + "." + tok + ".mail"
        with open(os.path.join(outbox, safe), "w") as fh:
            fh.write("To: %s\nFrom: list-owner@example.test\nSubject: subscription confirmation\n\n"
                     "Reply with token %s to confirm subscription.\n" % (addr, tok))
        print("token " + tok)
    elif cmd == "confirm":
        addr = sys.argv[2] if len(sys.argv) > 2 else ""
        tok = sys.argv[3] if len(sys.argv) > 3 else ""
        pend = read_rows(pending)
        expect = token_of(pend, addr)
        if expect is None or expect != tok:
            sys.stderr.write("confirm rejected for %s\n" % addr)
            sys.exit(7)
        mem = [r for r in read_rows(members) if r[0] != addr]
        mem.append([addr])
        write_rows(members, mem)
        pend = [r for r in pend if r[0] != addr]
        write_rows(pending, pend)
    elif cmd == "unsubscribe":
        addr = sys.argv[2] if len(sys.argv) > 2 else ""
        write_rows(members, [r for r in read_rows(members) if r[0] != addr])
        write_rows(pending, [r for r in read_rows(pending) if r[0] != addr])
    elif cmd == "membership":
        for row in sorted(read_rows(members)):
            print(row[0])
    elif cmd == "pending":
        for row in read_rows(pending):
            if len(row) >= 2:
                print("%s\t%s" % (row[0], row[1]))
    else:
        sys.stderr.write("unknown command: %s\n" % cmd)
        sys.exit(1)


if __name__ == "__main__":
    main()