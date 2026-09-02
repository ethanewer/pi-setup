#!/usr/bin/env python3
"""Atlas-Red: a compact, fully deterministic CoreWars-style MARS engine.

Pure stdlib, no randomness, no OS calls.  A battle between two fixed warriors
always yields the same result, so the same engine is used by an author while
developing a warrior and by an independent verifier while confirming it wins.

Memory ring: CORE cells. Each cell is one instruction packed as a list:

    [ op, a_imm, a_val, b_imm, b_val ]

  op     : OPS.index(op)    (DAT MOV ADD SUB JMP JMZ DJZ SPL)
  _imm   : 0 = PC-relative operand; 1 = immediate literal

A process that executes a cell marks that cell as owned by its fighter; owned
cell counts break ties when the step budget is exhausted (MITOL-style run).
"""
import json
import os
import sys

OPS = ["DAT", "MOV", "ADD", "SUB", "JMP", "JMZ", "DJZ", "SPL"]
CORE = 1024
MAXPROC = 2048
MAXSTEPS = 900

WAR_BASE = 40
OPP_BASE = CORE // 2


def arg_val(tok):
    if tok.startswith("#"):
        return [1, int(tok[1:])]
    return [0, int(tok)]


def parse(line):
    toks = line.split(";", 1)[0].split()
    if not toks:
        return None
    op = toks[0].upper()
    if op not in OPS:
        return None
    a = arg_val(toks[1]) if len(toks) > 1 else [0, 0]
    b = arg_val(toks[2]) if len(toks) > 2 else [0, 0]
    return [OPS.index(op), a[0], a[1], b[0], b[1]]


def assemble(text):
    cells = []
    for line in text.splitlines():
        cell = parse(line)
        if cell is not None:
            cells.append(cell)
    return cells


def load(text, base, ring):
    for i, cell in enumerate(assemble(text)):
        ring[(base + i) % len(ring)] = cell


def new_ring():
    return [[OPS.index("DAT"), 0, 0, 0, 0] for _ in range(CORE)]


def owner_counts(owner):
    c1 = sum(1 for k in range(CORE) if owner[k] == 1)
    c2 = sum(1 for k in range(CORE) if owner[k] == 2)
    return c1, c2


def battle(warrior_text, opp_text, war_base=WAR_BASE, opp_base=OPP_BASE,
           maxsteps=MAXSTEPS, maxproc=MAXPROC, detail=False):
    def verdict(result, stats):
        return (result, stats) if detail else result
    ring = new_ring()
    ring = new_ring()
    owner = [0] * CORE
    load(warrior_text, war_base, ring)
    load(opp_text, opp_base, ring)
    mv = list(assemble(warrior_text))
    mo = list(assemble(opp_text))

    procs = []
    if mv:
        procs.append((1, war_base))
        for i in range(len(mv)):
            owner[(war_base + i) % CORE] = 1
    if mo:
        procs.append((2, opp_base))
        for i in range(len(mo)):
            owner[(opp_base + i) % CORE] = 2

    for _ in range(maxsteps):
        a1 = any(sid == 1 for sid, _ in procs)
        a2 = any(sid == 2 for sid, _ in procs)
        if (not a1) and a2:
            return verdict(2, {"elim": "opponent"})
        if a1 and (not a2):
            return verdict(1, {"elim": "warrior"})
        if not procs:
            c1, c2 = owner_counts(owner)
            return verdict(1 if c1 > c2 else 0, {"mutual": True, "own": c1, "opp": c2})
        snapshot = procs[:]
        nxt = []
        for (side, pc) in snapshot:
            op, aimm, aval, bimm, bval = ring[pc]
            owner[pc] = side
            src = (pc + aval) % CORE
            dst = (pc + bval) % CORE
            adv = (pc + 1) % CORE
            if op == 0:                 # DAT
                continue
            if op == 7:                 # SPL
                if len(nxt) < maxproc:
                    nxt.append((side, src))
            if op == 1:                 # MOV
                if aimm:
                    ring[dst] = [OPS.index("DAT"), 0, aval % CORE, 0, 0]
                else:
                    ring[dst] = ring[src][:]
            elif op == 2:               # ADD
                v = aval if aimm else ring[src][2]
                ring[dst][2] = (ring[dst][2] + v) % CORE
            elif op == 3:               # SUB
                v = aval if aimm else ring[src][2]
                ring[dst][2] = (ring[dst][2] - v) % CORE
            elif op == 4:               # JMP
                adv = (pc + aval) % CORE if (not aimm) else (aval % CORE)
            elif op == 5:               # JMZ
                if (aval if aimm else ring[src][2]) == 0:
                    adv = (pc + bval) % CORE
            elif op == 6:               # DJZ
                ring[src][2] = (ring[src][2] - 1) % CORE
                if ring[src][2] == 0:
                    adv = (pc + bval) % CORE
            nxt.append((side, adv))
            if len(nxt) >= maxproc:
                break
        procs = nxt[:maxproc]

    c1, c2 = owner_counts(owner)
    if c1 > c2:
        return verdict(1, {"owner": c1, "opp": c2, "step": "budget"})
    if c2 > c1:
        return verdict(2, {"owner": c2, "opp": c1, "step": "budget"})
    return verdict(0, {"step": "budget", "tie": True})


def tournament(warrior_path, opp_dir=None):
    opp_dir = opp_dir or os.path.join(os.path.dirname(__file__), "opponents")
    war = open(warrior_path).read()
    rounds = []
    if os.path.isdir(opp_dir):
        for fname in sorted(os.listdir(opp_dir)):
            if fname.endswith((".red", ".war")):
                w = battle(war, open(os.path.join(opp_dir, fname)).read())
                rounds.append({"opponent": fname, "winner": w,
                               "warrior_wins": bool(w == 1)})
    return {"warrior": os.path.basename(warrior_path), "rounds": rounds,
            "all_wins": bool(rounds) and all(r["warrior_wins"] for r in rounds)}


if __name__ == "__main__":
    if len(sys.argv) == 3 and os.path.isfile(sys.argv[1]):
        w1 = open(sys.argv[1]).read()
        w2 = open(sys.argv[2]).read()
        print(json.dumps({"winner": battle(w1, w2)}))
    elif len(sys.argv) == 2 and os.path.isfile(sys.argv[1]):
        print(json.dumps(tournament(sys.argv[1])))
    else:
        print(json.dumps(tournament("warrior.red")))
