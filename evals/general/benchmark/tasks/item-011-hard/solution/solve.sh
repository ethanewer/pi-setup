#!/bin/bash
# Oracle port of the grouped GnuCOBOL report to Python 3.
set -euo pipefail

cat > /app/port.py <<'PY_EOF'
def main():
    with open("/app/port_input.dat") as f:
        lines = [ln.rstrip("\n").rstrip("\r") for ln in f]

    first = True
    prev = None
    dept_tot = 0
    grand = 0
    cnt = 0
    out = []

    for ln in lines:
        if len(ln) < 43:
            continue
        ident = int(ln[0:6])
        name = ln[7:25]
        dept = int(ln[26:28])
        rate = int(ln[29:34])
        yrs = int(ln[35:37])
        bonus = int(ln[38:43])

        annual_cents = rate * 12
        inc_cents = (bonus * 100) // yrs if yrs > 0 else 0
        total_cents = annual_cents + inc_cents

        if first:
            first = False
            prev = dept
        else:
            if dept != prev:
                out.append(sub_line(prev, dept_tot))
                dept_tot = 0
                prev = dept

        dept_tot += total_cents
        grand += total_cents
        cnt += 1

        out.append(detail_line(ident, name, annual_cents, total_cents))

    out.append(sub_line(prev, dept_tot))
    out.append(grand_line(cnt, grand))

    with open("/app/port_output.txt", "w") as f:
        f.write("\n".join(out) + "\n")

def detail_line(ident, name, annual_cents, total_cents):
    a = f"{annual_cents // 100:06d}.{annual_cents % 100:02d}"
    t = f"{total_cents // 100:06d}.{total_cents % 100:02d}"
    return f"D{ident:06d} {name} {a} {t}"

def sub_line(dept, dept_tot):
    return f"S{dept:02d} {dept_tot // 100:08d}.{dept_tot % 100:02d}".ljust(46)

def grand_line(cnt, grand):
    return f"G{cnt:06d} {grand // 100:08d}.{grand % 100:02d}".ljust(46)

main()
PY_EOF