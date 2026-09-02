FROM bench-base:python-3.12

WORKDIR /app

# biopython is optional (stdlib is sufficient) but available for convention use
RUN python3 -m pip install -q biopython 2>/dev/null || true

COPY files/ /app/