FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

# The task is built with the Go programming language ("golang"; `go` toolchain).
# Only the standard library is used, so no further packages are needed and the
# build works fully offline.
RUN apt-get update -qq && \
    apt-get install -y -qq golang-go && \
    rm -rf /var/lib/apt/lists/*

# The trial uses a single CPU and no numeric libraries; nothing to pin here.
# `go` needs a writable build cache regardless of which user the sweep picks;
# point it at a world-writable location. The workspace must also be writable
# so the agent can lay down the deliverable sources and binary.
ENV GOCACHE=/tmp/gocache

WORKDIR /app
RUN mkdir -p /tmp/gocache && chmod 0777 /tmp/gocache && chmod 0777 /app
COPY files/ /app/