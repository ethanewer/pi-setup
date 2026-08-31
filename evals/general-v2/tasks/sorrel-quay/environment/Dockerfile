FROM bench-base:python-3.12

WORKDIR /app

# Sorrel Quay single-node cluster: site-config templates (placeholders), the
# name-daemon emulator, and a visible smoke probe. The verifier starts the
# daemons itself using the agent's configured site files.
COPY files/ /app/

RUN chmod +x /app/sbin/name-daemon.py /app/bin/smoke_probe.py \
    && mkdir -p /app/run /app/data
