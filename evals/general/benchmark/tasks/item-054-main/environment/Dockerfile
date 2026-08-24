FROM bench-base:ubuntu-24.04
WORKDIR /app
RUN apt-get update && apt-get install -y gcc libc6-dev binutils && rm -rf /var/lib/apt/lists/*

# Build the reference renderer from source, then remove the source so only the
# binary ships (the agent must reverse-engineer it).
RUN mkdir -p /app/pov
COPY files/render_ref.c /tmp/build/render_ref.c
RUN gcc -O2 -o /app/pov/render_ref /tmp/build/render_ref.c && rm -rf /tmp/build

COPY files/README.md /app/pov/README.md
COPY files/check.py /app/pov/check.py
COPY files/scene0.pov /app/pov/scene0.pov

# Deterministic sample output produced by the reference itself.
RUN cd /app/pov && ./render_ref scene0.pov scene0.ppm