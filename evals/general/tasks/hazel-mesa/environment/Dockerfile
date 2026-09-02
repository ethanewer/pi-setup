# hazel-mesa — compose-driven Postgres warehouse export.
#
# A PostgreSQL instance is built from distro packages and controlled by an
# observatory role script (/opt/obsctl/dbctl.sh) that lives in the image, not
# in the deliverables. The compose-style stack description shipped in
# /app/warehouse describes the exact instance the agent must connect to
# (host port 5433, SCRAM password auth for the app role).

FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        postgresql postgresql-client python3 procps ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Scenario fixture: the compose-style stack description (NOT the answer).
COPY files/ /app/

# Infrastructure: DB bootstrap + control script + entrypoint (in image only).
COPY obsctl/ /opt/obsctl/
RUN chmod +x /opt/obsctl/dbctl.sh /opt/obsctl/entry.sh

WORKDIR /app

ENTRYPOINT ["/opt/obsctl/entry.sh"]
CMD ["bash"]
