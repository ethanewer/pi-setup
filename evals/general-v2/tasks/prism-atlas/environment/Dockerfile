FROM bench-base:ubuntu-24.04

WORKDIR /app

# CLI tooling under test: vim (for the headless macro pass) and python3.
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        vim \
        python3 \
    && rm -rf /var/lib/apt/lists/*

# Build the fixed input fixtures (call-site logs, depot rows, initial state).
COPY files/ /appdata/
RUN python3 /appdata/gen_fixture.py / \
    && rm -rf /appdata

# The task is otherwise authored entirely by the agent in /app.