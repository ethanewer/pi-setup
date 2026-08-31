# gale-quarry: O(n) drifting-mote simulation, serial + OpenMP from one source.
#
# The container ships only the scenario; the agent authors src/motes.c and
# launch.py. The verifier rebuilds nothing itself: it executes the agent's
# launch.py and then re-runs the produced binaries directly.
FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update >/dev/null 2>&1 && \
    apt-get install -y --no-install-recommends \
      gcc libc6-dev libgomp1 make >/dev/null 2>&1 && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY files/ /app/
