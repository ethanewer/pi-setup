FROM bench-base:python-3.12

WORKDIR /app

# Minimal runtime: the `requests` HTTP client is the only extra dependency.
RUN pip install --no-cache-dir -q requests

# Read-only fixtures: the tiny cloud emulator, its seeded in-memory-store on
# disk, a raw RPC sample to normalize, and the account fixtures/dev target list.
COPY files/ /app/

# Deliverables (created by the agent) live under /app alongside these fixtures.