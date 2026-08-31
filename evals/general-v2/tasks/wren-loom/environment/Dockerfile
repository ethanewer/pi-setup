# wren-loom: a mailing-list configuration task for the Foundry Commons
# makerspace. A tiny list daemon (loopd) is installed in the image and started
# by the entrypoint; it reads its configuration ONLY from the canonical path
# /etc/loopd/lists.conf and re-reads it on SIGHUP. The agent must provision
# the canonical config from a spec CSV and make the live daemon honor it.

FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        procps ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Infrastructure: the list daemon + entrypoint (image only, not deliverables).
COPY loopd/ /opt/loopd/
RUN chmod +x /opt/loopd/entry.sh && mkdir -p /etc/loopd /run

# Scenario fixture: the list specification the agent provisions from.
# This is NOT the answer; the answer is the canonical config + a live daemon.
COPY files/ /app/

ENTRYPOINT ["/opt/loopd/entry.sh"]
CMD ["bash"]

# Harbor's `compose up --wait` blocks until the container is healthy, so the
# agent/verifier never race the daemon startup in the entrypoint.
HEALTHCHECK --interval=1s --timeout=3s --start-period=60s --retries=30 \
    CMD python3 -c "import socket;s=socket.create_connection(('127.0.0.1',7871),2);s.sendall(b'PING\n');assert s.recv(64).startswith(b'PONG')" || exit 1
