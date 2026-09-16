FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

# Go 1.22 toolchain (verified: golang-go 1.22.2 ships /usr/bin/go).
RUN apt-get update -qq && \
    apt-get install -y -qq golang-go curl >/dev/null 2>&1 && \
    rm -rf /var/lib/apt/lists/*

# The harness may run agent and verifier steps as different users (root or
# uid 1000). Go's build cache and module cache must be writable for either,
# and /app must be writable so the agent can author the service in place.
RUN mkdir -p /tmp/gocache /tmp/gopath && \
    chmod 1777 /tmp/gocache /tmp/gopath
ENV GOCACHE=/tmp/gocache \
    GOPATH=/tmp/gopath \
    GOMODCACHE=/tmp/gopath/pkg/mod

WORKDIR /app
RUN chmod 777 /app

COPY files/ /app/