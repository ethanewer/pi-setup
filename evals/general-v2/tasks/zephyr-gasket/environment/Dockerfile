FROM bench-base:python-3.12

WORKDIR /app

# Maze interface + reference fixture + visible game positions.
# Pure-Wiki/python; no GPU, no systemd, single container.
COPY files/ /app/

WORKDIR /app