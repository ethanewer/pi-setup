FROM bench-base:python-3.12

# The shipped demo repository is built with `make`, so the image needs it.
RUN apt-get update && apt-get install -y --no-install-recommends make \
    && rm -rf /var/lib/apt/lists/*

# The runner parses workflow YAML and the CI suite drives pytest. Pins are
# exact per suite contract.
RUN pip install --no-cache-dir pyyaml==6.0.3 pytest==9.1.1

WORKDIR /app
COPY files/ /app/