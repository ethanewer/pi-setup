FROM bench-base:python-3.12

WORKDIR /app

RUN python3 - <<'PYEOF'
rows = [
    [10, 20, 200, 255],
    [30, 128, 129, 0],
    [100, 90, 70, 128],
    [255, 250, 0, 200],
]
w, h = len(rows[0]), len(rows)
lines = ["P2", f"{w} {h}", "255"]
for r in rows:
    lines.append(" ".join(str(v) for v in r))
open('/app/image.pgm', 'w').write("\n".join(lines) + "\n")
PYEOF