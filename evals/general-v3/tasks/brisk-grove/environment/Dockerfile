FROM bench-base:ubuntu-24.04

WORKDIR /app

# com.cn openjdk (javac needed only to compile the daemon jar at build time;
# the runtime keeps only the JRE classes we ship in the jar). python3 ships
# with the ubuntu base.
RUN apt-get update \
    && apt-get install -y --no-install-recommends openjdk-17-jdk-headless \
    && rm -rf /var/lib/apt/lists/*

# Site templates, the daemon source, the gateway + client check tools, and the
# SLURM stand-in (+nodes.json state) and launcher resolver.
COPY files/config/ /app/config/
COPY files/src/sinemu/Daemon.java /app/mds/Daemon.java
COPY files/src/bin/ /app/bin/
COPY files/opt/mdsl /opt/mdsl

# Compile the daemon jar (uses the JDK just installed).
RUN mkdir -p /tmp/daemon-out \
    && javac -d /tmp/daemon-out /app/mds/Daemon.java \
    && (cd /tmp/daemon-out && jar cf /app/mds/daemon.jar org) \
    && rm -rf /tmp/daemon-out

RUN chmod +x /opt/mdsl/bin/sinfo /opt/mdsl/bin/mdsl-resolve \
    && chmod +x /app/bin/gateway.py /app/bin/client_check.py

RUN mkdir -p /app/run