FROM bench-base:ubuntu-24.04

WORKDIR /app

# telnet client for interactive text-protocol connections
RUN apt-get update && apt-get install -y telnet && rm -rf /var/lib/apt/lists/*

COPY files/server.py /app/server.py