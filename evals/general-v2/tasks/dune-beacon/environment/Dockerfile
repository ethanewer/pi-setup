FROM bench-base:ubuntu-24.04

WORKDIR /app

# PTY / scripting / vim tooling used by the interactive parts of the task.
# python3 + the stdlib sqlite3 module back the maze server and the text
# adventure's persistence. Kept deliberate and small.
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 libsqlite3-0 vim \
    && rm -rf /var/lib/apt/lists/*

# The interactive maze server, the text adventure, the shipped maze instances,
# the reference maze fixture and the vim capture/source fixtures the agent must
# reverse / target.
COPY files/ /app/

RUN python3 -m py_compile /app/server.py /app/adventure.py && \
    chmod +x /app/server.py /app/adventure.py