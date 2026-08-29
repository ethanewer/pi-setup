#!/usr/bin/env python3
"""The Dune Beacon text adventure: a small interactive terminal game.

You read commands from stdin; the game prints room descriptions and outcomes to
stdout (every block flushed). Reach the ending by taking the key, opening the
gate, sailing to the tower islet, climbing to the lantern gallery and typing
`light`. Type `quit` on its own to leave the game, which is the only thing that
commits your journey to the SQLite database at /app/state/beacon.db. Killing
the process persists nothing.
"""
import os
import sqlite3
import sys

ENDING = "THE BEACON IS WOKEN; the storm breaks and the last gate is calmed."
DB_PATH = "/app/state/beacon.db"

# room graph: room -> {direction: (target, need_gate_open, need_boat)}
ROOMS = {
    "courtyard": {"n": ("gatehouse", False, False), "s": ("stables", False, False)},
    "stables": {"n": ("courtyard", False, False)},
    "gatehouse": {"s": ("courtyard", False, False), "e": ("causeway", True, False)},
    "causeway": {"w": ("gatehouse", True, False), "e": ("pier", True, False)},
    "pier": {"w": ("causeway", True, False), "up": ("isle", True, True)},
    "isle": {"up": ("tower", True, False), "d": ("pier", True, False)},
    "tower": {"up": ("gallery", True, False), "d": ("isle", True, False)},
    "gallery": {"d": ("tower", True, False)},
}
DESC = {
    "courtyard": "a stone courtyard ringed by walls",
    "stables": "a humble stables with a key lying in the straw",
    "gatehouse": "a mottled gatehouse with a great iron gate to the east",
    "causeway": "a causeway above dark water",
    "pier": "a wooden pier with a single boat moored here",
    "isle": "the lighthouse isle, with a tall tower above",
    "tower": "a winding stair that climbs to a lantern gallery",
    "gallery": "the copper lantern glimmering in the cupola",
}


class Game(object):
    def __init__(self):
        self.room = "courtyard"
        self.has_key = False
        self.gate_open = False
        self.boat = False
        self.ended = False
        self.visited = ["courtyard"]

    def describe(self, room):
        return "You are in %s: %s. Exits: %s." % (
            room, DESC.get(room, "a place"),
            ", ".join(sorted(ROOMS[room].keys())))

    def move(self, room):
        self.room = room
        if room not in self.visited:
            self.visited.append(room)

    def act(self, cmd):
        verb = cmd.split()[0].lower()
        if verb in ("go", "walk"):
            if len(cmd.split()) < 2:
                return "Which way?"
            return self._move(cmd.split()[1])
        if verb in ("n", "s", "e", "w", "up", "d"):
            return self._move(verb)
        if verb == "take":
            if self.room == "stables" and not self.has_key:
                self.has_key = True
                return "You pick up the rusted key."
            if self.room == "pier" and not self.boat:
                self.boat = True
                return "You cast off from the pier; the little boat carries you."
            return "There is nothing to take here."
        if verb == "open":
            if self.room == "gatehouse":
                if self.has_key:
                    self.gate_open = True
                    return "You turn the key and the great gate swings open."
                return "The gate is locked. You need the key."
            return "There is nothing to open here."
        if verb == "light":
            if self.room == "gallery":
                self.ended = True
                return self.describe("gallery") + " The lantern blazes:\n\n" + ENDING
            return "There is no burning lantern here."
        if verb == "look":
            return self.describe(self.room)
        if verb == "inventory":
            return "You carry: %s" % ("the key" if self.has_key else "nothing")
        if verb == "help":
            return "go/walk <s,e,w,n,up,d>; or a bare direction; take key; take boat; open gate; light; look; inventory; quit"
        if verb == "quit":
            return "__QUIT__"
        return "I do not understand that."

    def _move(self, key):
        key = key.lower()
        if key not in ROOMS[self.room]:
            return "You cannot go %s from here." % key
        target, need_gate, need_boat = ROOMS[self.room][key]
        if need_gate and not self.gate_open:
            return "The iron gate is shut; you must 'open gate' first."
        if need_boat and not self.boat:
            return "The way across the water needs a boat (take boat at the pier)."
        self.move(target)
        return self.describe(self.room)


def flush_db(game):
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    con = sqlite3.connect(DB_PATH)
    con.execute(
        "CREATE TABLE IF NOT EXISTS players (pid INTEGER PRIMARY KEY,"
        " reached_ending INTEGER, key_taken INTEGER, gate_opened INTEGER,"
        " boat INTEGER, rooms_visited INTEGER)")
    con.execute(
        "CREATE TABLE IF NOT EXISTS events (eid INTEGER PRIMARY KEY AUTOINCREMENT,"
        " room TEXT, seed INTEGER)")
    con.execute(
        "INSERT INTO players (reached_ending, key_taken, gate_opened, boat,"
        " rooms_visited) VALUES (?,?,?,?,?)",
        (1 if game.ended else 0, 1 if game.has_key else 0,
         1 if game.gate_open else 0, 1 if game.boat else 0, len(game.visited)))
    for room in game.visited:
        con.execute("INSERT INTO events (room, seed) VALUES (?,?)", (room, 7))
    con.commit()
    con.close()


def mainloop():
    game = Game()
    print("Welcome to the Dune Beacon Lighthouse.")
    print(game.describe("courtyard"))
    print("> ", end="", flush=True)
    for raw in sys.stdin:
        line = raw.rstrip("\r\n")
        if not line.strip():
            continue
        if line.strip().lower() == "quit":
            flush_db(game)
            print("You leave the lighthouse; the records are written.")
            break
        out = game.act(line)
        if out == "__QUIT__":
            flush_db(game)
            print("You leave the lighthouse; the records are written.")
            break
        print(out)
        print("> ", end="", flush=True)


if __name__ == "__main__":
    mainloop()