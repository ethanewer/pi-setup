#!/usr/bin/env python3
"""kestrel-vault -- a small interactive vault-sealing game.

Run:  python3 vault.py <scenario.json> [--db <db_path>]

Reads one command per line from stdin, answers with a single response line per
command (flushed). State is ONLY written to the SQLite database on the clean
`quit` command path. If the process is killed, aborted, or stdin hits EOF
before a clean `quit`, nothing is written.

Command protocol (single-token names/gems):
  look            -> CONTAINERS <name1, name2, ...>
  search <name>   -> FOUND <gem> | EMPTY | NO-SUCH-CONTAINER
  take <gem>      -> TAKEN <gem> | ALREADY-HELD | NOT-FOUND
  place <gem>     -> PLACED <gem> | NOT-HELD
  seal            -> SEALED <ending message> | REJECTED missing=<k>
  status          -> HELD <csv> PLACED <csv>
  quit            -> BYE   (persists, then exits 0)
  anything else   -> UNKNOWN
"""
import json
import os
import sqlite3
import sys


def main():
    args = sys.argv[1:]
    if not args:
        print("usage: vault.py <scenario.json> [--db <db_path>]", file=sys.stderr)
        sys.exit(2)
    scenario_path = args[0]
    db_path = "/app/state/vault.db"
    if "--db" in args:
        i = args.index("--db")
        db_path = args[i + 1]

    with open(scenario_path, "r", encoding="utf-8") as fh:
        sc = json.load(fh)
    keeper = sc["keeper"]
    containers = sc["containers"]            # [{"name": ..., "gem": ...}, ...]
    required = [c["gem"] for c in containers]
    ending = sc["ending"]

    found = set()
    held = set()
    placed = set()
    moves = 0
    events = []
    quit_cleanly = False
    completed = 0

    print("VAULT-READY keeper=%s containers=%d" % (keeper, len(containers)), flush=True)

    for line in sys.stdin:
        cmd = line.strip()
        if not cmd:
            continue
        moves += 1
        parts = cmd.split()
        op = parts[0].lower()
        if op == "look":
            print("CONTAINERS " + ", ".join(c["name"] for c in containers), flush=True)
        elif op == "search":
            name = parts[1] if len(parts) > 1 else ""
            c = next((c for c in containers if c["name"] == name), None)
            if c is None:
                print("NO-SUCH-CONTAINER", flush=True)
            elif c["gem"] in found:
                print("EMPTY", flush=True)
            else:
                found.add(c["gem"])
                print("FOUND " + c["gem"], flush=True)
        elif op == "take":
            g = parts[1] if len(parts) > 1 else ""
            if g in held:
                print("ALREADY-HELD", flush=True)
            elif g in found:
                held.add(g)
                print("TAKEN " + g, flush=True)
            else:
                print("NOT-FOUND", flush=True)
        elif op == "place":
            g = parts[1] if len(parts) > 1 else ""
            if g in held:
                held.discard(g)
                placed.add(g)
                events.append(("place", g))
                print("PLACED " + g, flush=True)
            else:
                print("NOT-HELD", flush=True)
        elif op == "seal":
            if placed == set(required) and len(placed) == len(required):
                completed = 1
                events.append(("seal", "ok"))
                print("SEALED " + ending, flush=True)
            else:
                events.append(("seal", "rejected"))
                print("REJECTED missing=%d" % len(set(required) - placed), flush=True)
        elif op == "status":
            print("HELD %s PLACED %s" % (",".join(sorted(held)), ",".join(sorted(placed))),
                  flush=True)
        elif op == "quit":
            print("BYE", flush=True)
            quit_cleanly = True
            break
        else:
            print("UNKNOWN", flush=True)

    if not quit_cleanly:
        # Killed, aborted, or EOF before the clean exit path: write nothing.
        sys.exit(1)

    # --- clean exit path only: flush session state to the database ---
    parent = os.path.dirname(db_path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    conn = sqlite3.connect(db_path)
    conn.execute(
        "CREATE TABLE IF NOT EXISTS sessions ("
        "id INTEGER PRIMARY KEY, keeper TEXT, gems_found INTEGER, "
        "gems_placed INTEGER, moves INTEGER, completed INTEGER)"
    )
    conn.execute(
        "CREATE TABLE IF NOT EXISTS events ("
        "id INTEGER PRIMARY KEY, session_id INTEGER, kind TEXT, detail TEXT)"
    )
    cur = conn.execute(
        "INSERT INTO sessions (keeper, gems_found, gems_placed, moves, completed) "
        "VALUES (?, ?, ?, ?, ?)",
        (keeper, len(found), len(placed), moves, completed),
    )
    sid = cur.lastrowid
    conn.executemany(
        "INSERT INTO events (session_id, kind, detail) VALUES (?, ?, ?)",
        [(sid, k, d) for (k, d) in events],
    )
    conn.commit()
    conn.close()
    sys.exit(0)


if __name__ == "__main__":
    main()
