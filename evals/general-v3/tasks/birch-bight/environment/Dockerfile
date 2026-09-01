# birch-bight: Larkfield Airshed telemetry pull. A Postgres instance is built
# from distro packages and controlled by an image-local role script
# (/opt/airctl/dbctl.sh). The compose-style credentials shipped in
# /app/airshed describe the exact instance the agent must connect to; TCP
# auth is SCRAM so wrong credentials are genuinely refused.

FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        postgresql postgresql-client procps ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Postgres driver for the deliverable program (pinned for determinism).
RUN python3 -m pip install --no-cache-dir psycopg2-binary==2.9.10

WORKDIR /app

# Scenario fixture: the compose-style service description (NOT the answer).
COPY files/ /app/

# Infrastructure: DB bootstrap + control script + entrypoint (image only).
COPY airctl/ /opt/airctl/
RUN chmod +x /opt/airctl/dbctl.sh /opt/airctl/entry.sh

ENTRYPOINT ["/opt/airctl/entry.sh"]
CMD ["bash"]
