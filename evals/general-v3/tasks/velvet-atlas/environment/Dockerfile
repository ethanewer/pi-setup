FROM bench-base:python-3.12

WORKDIR /app

# Read-only fixtures: the registry emulator, the seeded store, and the
# cancellation list. Deliverables (created by the agent) live under /app.
COPY files/ /app/
