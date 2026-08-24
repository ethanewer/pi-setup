FROM bench-base:python-3.12

WORKDIR /app

RUN cat > /app/child.py <<'PYEOF'
import sys
line = sys.stdin.readline()
sys.stdout.write(line.upper())
PYEOF