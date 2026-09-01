FROM bench-base:python-3.12

WORKDIR /app

# numpy is the only runtime dependency (policy forward pass + seeded env).
RUN pip install --no-cache-dir --quiet numpy

# Read-only evaluation fixture (visible case).
COPY files/ /app/
