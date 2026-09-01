FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --no-cache-dir -q numpy

# Read-only fixture: the clan-dialect word relations.
COPY files/ /app/
