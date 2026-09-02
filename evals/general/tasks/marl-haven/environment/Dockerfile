FROM bench-base:python-3.12

WORKDIR /app

# numpy for the .npy matrix deliverable.
RUN python3 -m pip install --no-cache-dir numpy

COPY files/ /app/.fixtures/

# Materialize the visible fixtures (binary SBT-1 capture + query) into /app.
RUN python3 /app/.fixtures/build_fixtures.py && rm -rf /app/.fixtures

WORKDIR /app
