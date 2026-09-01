FROM bench-base:python-3.12

WORKDIR /app

# The visible reference case for the arrangement engine.
COPY files/instance/ /app/instance/

RUN pip install --no-cache-dir scipy >/dev/null 2>&1 || true
