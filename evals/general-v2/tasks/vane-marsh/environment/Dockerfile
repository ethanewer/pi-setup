# vane-marsh: a single local PostgreSQL "metering service" whose connection
# settings are described ONLY by a compose-style file shipped in /app/grid.
# The agent must derive host/port/db/user/password from that file and connect.

FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /app

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        postgresql postgresql-client procps ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Scenario fixtures: the compose-style credential description the agent must
# read to derive the connection. NOT the answer itself.
COPY files/ /app/

# Infrastructure: DB bootstrap + control script + entrypoint (image-only).
COPY gridctl/ /opt/gridctl/
RUN chmod +x /opt/gridctl/dbctl.sh /opt/gridctl/entry.sh

ENTRYPOINT ["/opt/gridctl/entry.sh"]
CMD ["bash"]
