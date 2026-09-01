# granary-ledge: a low-stock inventory report driven off a compose-described
# Postgres store. The instance is provisioned by an image-local role script
# (/opt/groundctl/dbctl.sh) to match the credentials published in
# /app/deploy/stack.yml; the agent must derive host/port/user/db/password from
# that file and open a live connection.

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

# Scenario fixture: the compose-style stack description (NOT the answer).
COPY files/ /app/

# Infrastructure: DB bootstrap + control script + entrypoint (in image only).
COPY groundctl/ /opt/groundctl/
RUN chmod +x /opt/groundctl/dbctl.sh /opt/groundctl/entry.sh

ENTRYPOINT ["/opt/groundctl/entry.sh"]
CMD ["bash"]
