# yoke-inlet: TLS reverse-proxy front door with canary splitting, failover and a
# custom access-log format. Builds on bench-base:ubuntu-24.04 with plain apt
# packages only (nginx 1.24, openssl, small process-control utilities).

FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
        nginx \
        openssl \
        procps \
        psmisc \
        curl \
        ca-certificates \
        python3 \
    && rm -rf /var/lib/apt/lists/*

# Prove the toolchain is present; a missing piece fails the build loudly.
RUN nginx -v 2>&1 | tee /dev/stderr && \
    openssl version && \
    python3 --version && \
    curl --version | head -1

# Runtime state for the agent's stack (logs, pid, TLS, temp dirs) must be
# writable and traversable by whichever uid the harness runs (root or 1000).
RUN mkdir -p /app/logs /app/run /app/tls && \
    chmod 1777 /app/logs /app/run /app/tls

WORKDIR /app

COPY files/ /app/

RUN chmod -R a+rX /app/upstreams

CMD ["/bin/bash"]