FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y gcc libc6-dev make && rm -rf /var/lib/apt/lists/*

# The agent rewrites /app/netlist.c and must recompile it with:
#   gcc -O2 -o netlist netlist.c
COPY files/netlist.c /app/netlist.c