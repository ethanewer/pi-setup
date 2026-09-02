# brisk-kiln — listd mailing-list manager provisioning.
#
# The daemon (in image only, not a deliverable) reads its configuration ONLY
# from the canonical path /etc/listd/lists.conf and serves an HTTP API on
# 127.0.0.1:8418. The agent must author the configuration and install it at
# the canonical path via the idempotent installer.

FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        python3 procps curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Daemon + control script (in image only, never the answer).
COPY listd/ /opt/listd/
RUN chmod +x /opt/listd/ctl.sh /opt/listd/listd.py && \
    touch /var/log/listd.log

WORKDIR /app
