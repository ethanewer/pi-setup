# gull-wharf: a single Postgres connection-report exercise. A Postgres
# instance is built from distro packages and controlled by a small role script
# (/opt/tidectl/dbctl.sh) that lives in the image, not in the deliverables.
# The compose-style credentials shipped in /app/stack describe the exact
# instance the agent must connect to (TCP auth is scram, so the password in
# the compose file genuinely matters).

FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        postgresql postgresql-client python3 procps ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Scenario fixture: the compose-style service description (NOT the answer).
COPY files/ /app/

# Infrastructure: DB bootstrap + control script + entrypoint (in image only).
COPY tidectl/ /opt/tidectl/
RUN chmod +x /opt/tidectl/dbctl.sh /opt/tidectl/entry.sh

ENTRYPOINT ["/opt/tidectl/entry.sh"]
CMD ["bash"]
