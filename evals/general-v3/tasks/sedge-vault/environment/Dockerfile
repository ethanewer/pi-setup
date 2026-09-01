# sedge-vault: a Sedgevault Field Archive specimen export. A single Postgres
# instance is built from distro packages and controlled by an archive role
# script (/opt/archivectl/dbctl.sh) that lives in the image, not in the
# deliverables. The compose-style stack description shipped in /app/archive
# documents the exact instance (nonstandard published port, db, user,
# password) the agent must derive and use.

FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /app

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        postgresql postgresql-client python3 procps ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Scenario fixture: the compose-style stack description the agent reads to
# derive host/port/db/user/password. This is NOT the answer.
COPY files/ /app/

# Infrastructure: DB bootstrap + control script + entrypoint (image only).
COPY archivectl/ /opt/archivectl/
RUN chmod +x /opt/archivectl/dbctl.sh /opt/archivectl/entry.sh

ENTRYPOINT ["/opt/archivectl/entry.sh"]
CMD ["bash"]

# Harbor's `compose up --wait` blocks until the container is healthy, so the
# agent/verifier never race the one-time cluster bootstrap in the entrypoint.
HEALTHCHECK --interval=1s --timeout=3s --start-period=90s --retries=60 \
    CMD pg_isready -h 127.0.0.1 -p 5541 -q || exit 1
