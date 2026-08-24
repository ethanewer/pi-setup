#!/bin/bash
# Oracle: port of legacy.cob to Python 3.
set -euo pipefail

cat > /app/port.py <<'PY_EOF'
def main():
    with open("/app/port_input.dat") as f:
        lines = [ln.rstrip("\n").rstrip("\r") for ln in f]
    out = []
    for ln in lines:
        if len(ln) < 40:
            continue
        ident = int(ln[0:6])
        name = ln[7:25]
        rate = int(ln[26:31])
        years = int(ln[32:34])
        bonus = int(ln[35:40])
        annual_cents = rate * 12
        if years > 0:
            inc_cents = (bonus * 100) // years
        else:
            inc_cents = 0
        total_cents = annual_cents + inc_cents
        line = (f"{ident:06d} {name} "
                f"{annual_cents // 100:06d}.{annual_cents % 100:02d} "
                f"{total_cents // 100:06d}.{total_cents % 100:02d}")
        out.append(line)
    with open("/app/port_output.txt", "w") as f:
        f.write("\n".join(out) + "\n")

main()
PY_EOF