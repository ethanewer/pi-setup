# quartz-cipher: a single Postgres WAL durability audit. A Postgres instance is
# built from distro packages and controlled by a small role script
# (/opt/wardctl/dbctl.sh) that lives in the image, not in the deliverables.
# The compose-style credentials shipped in /app/warehouse describe the exact
# instance the agent connects to.

FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        postgresql postgresql-client python3 procps ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Scenario fixtures: a compose-style description plus a key reference the agent
# reads to derive host/port/db/user/password. These are NOT the answer.
COPY files/ /app/

# Infrastructure: DB bootstrap + control script + entrypoint (in image only).
COPY wardctl/ /opt/wardctl/
RUN chmod +x /opt/wardctl/dbctl.sh /opt/wardctl/entry.sh

ENTRYPOINT ["/opt/wardctl/entry.sh"]
CMD ["bash"]