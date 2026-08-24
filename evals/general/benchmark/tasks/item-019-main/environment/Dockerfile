FROM bench-base:python-3.12

WORKDIR /app

# Original evidence snapshot (read-only inputs; the agent must NOT modify these).
COPY files/evidence/orders.db files/evidence/orders.db-wal /app/evidence/
COPY files/docs/incident.md files/docs/audit.csv /app/evidence/