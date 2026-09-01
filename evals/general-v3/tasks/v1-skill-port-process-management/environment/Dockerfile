FROM bench-base:ubuntu-24.04

# iproute2: ss. procps/lsof/psmisc: alternative listener introspection tools.
RUN apt-get update && apt-get install -y iproute2 procps lsof psmisc && rm -rf /var/lib/apt/lists/*

WORKDIR /app