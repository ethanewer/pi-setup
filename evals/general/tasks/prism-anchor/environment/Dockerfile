FROM bench-base:ubuntu-24.04

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        openssh-server sudo procps acl python3-pip && \
    python3 -m pip install --no-cache-dir --break-system-packages pytest && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY files/ /app/

RUN chmod 0755 /app/entrypoint.sh && \
    mkdir -p /srv && \
    chmod 0755 /app/entrypoint.sh

ENV PYTHONUNBUFFERED=1

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["/bin/bash"]