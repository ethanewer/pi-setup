# moor-atlas: a beacon-registry census driven off a compose-described
# Postgres store. Two clusters are provisioned by an image-local role script
# (/opt/moorctl/dbctl.sh): the authoritative registry described by
# /app/deploy/services.yml (host port 5581) and a retired DECOY registry with
# the same database name/credentials but an empty table on another port. The
# agent must derive host/port/user/db/password from the compose file alone.

FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        postgresql postgresql-client ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Python driver + YAML for the deliverable program (pinned, installed at build
# time only; no network is needed at run/verify time).
RUN pip install --no-cache-dir --no-input \
        "psycopg2-binary==2.9.10" "PyYAML==6.0.2"

WORKDIR /app

# Scenario fixture: the compose-style stack description. NOT the answer.
COPY files/ /app/

# Infrastructure: DB bootstrap + control script + entrypoint (in image only).
COPY moorctl/ /opt/moorctl/
RUN chmod +x /opt/moorctl/dbctl.sh /opt/moorctl/entry.sh

ENTRYPOINT ["/opt/moorctl/entry.sh"]
CMD ["bash"]
