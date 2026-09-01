; starter.red -- a minimal, non-winning skeleton that just hops in place, so it
; cannot beat the shipped holdouts.  Replace the body with a real strategy and
; iterate with:
;   python3 /app/corewar/core.py /app/warrior.red
; until every round in the printed tournament is a win.  A self-replicating
; "worm" (an instruction that keeps copying itself forward) combined with a
; division instruction that grows the worm into two worms is one classic way to
; overwhelm the ring.
JMP 0