# dunlin-shoal: a Larkspur Field Station telemetry archive. Postgres runs from
# distro packages and is controlled by /opt/dunctl/dbctl.sh (image
# infrastructure, not a deliverable). The compose-style credentials in
# /app/deploy describe the exact instance the agent must connect to
# (database/user/password and the published port 5533, deliberately not 5432).

FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        postgresql postgresql-client python3 procps ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Scenario fixture: the compose-style stack description. NOT the answer.
COPY files/ /app/

# Infrastructure: DB bootstrap + control script + entrypoint (in image only).
COPY dunctl/ /opt/dunctl/
RUN chmod +x /opt/dunctl/dbctl.sh /opt/dunctl/entry.sh

ENTRYPOINT ["/opt/dunctl/entry.sh"]
CMD ["bash"]
