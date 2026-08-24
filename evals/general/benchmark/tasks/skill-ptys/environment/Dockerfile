FROM bench-base:python-3.12

WORKDIR /app

RUN cat > /app/printer.py <<'PYEOF'
import time
for line in ['line one', 'line two', 'line three']:
    print(line)
    time.sleep(0.05)
PYEOF