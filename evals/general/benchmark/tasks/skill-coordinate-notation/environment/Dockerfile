FROM bench-base:python-3.12

WORKDIR /app

RUN python3 - <<'PYEOF'
lines = [
    '40°26\'46"N',
    '79°58\'56"W',
    '51°30\'30"N',
]
open('/app/coords.txt', 'w').write("\n".join(lines) + "\n")
PYEOF