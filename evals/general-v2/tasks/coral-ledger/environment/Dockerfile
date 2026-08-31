# coral-ledger: read-only port-ledger analytics environment
FROM bench-base:python-3.12

WORKDIR /app

COPY files/gen_db.py /opt/ledger/gen_db.py

# Deterministic production ledger (fixed seed).
RUN mkdir -p /app/data \
 && python3 /opt/ledger/gen_db.py /app/data/port.db 77 \
 && python3 -c "import sqlite3; c=sqlite3.connect('file:/app/data/port.db?mode=ro', uri=True); print('tables:', [r[0] for r in c.execute(\"SELECT name FROM sqlite_master WHERE type='table' ORDER BY name\")])"
