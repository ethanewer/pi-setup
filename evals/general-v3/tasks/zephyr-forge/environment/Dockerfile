FROM bench-base:python-3.12

WORKDIR /app

# The visible case fixtures for the forge engine.
COPY files/ /app/case/

RUN pip install --no-cache-dir scipy numpy highspy pulp >/dev/null 2>&1 || true