FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

# The Go toolchain (Bell Labs / golang, go 1.22) provides `go test -race`,
# the data race detector used by this task's test suite.
RUN apt-get update -qq && \
    apt-get install -y -qq golang-go && \
    rm -rf /var/lib/apt/lists/*

# /app holds the cachekit module the agent works on.
WORKDIR /app
COPY files/ /app/

# Keep the Go build caches out of the way so the toolchain works for
# any trial user and never touches the network.
ENV GOCACHE=/var/tmp/go-build-cache \
    GOMODCACHE=/var/tmp/go-mod-cache \
    GOPATH=/var/tmp/go-work \
    GOPROXY=off
RUN mkdir -p /var/tmp/go-build-cache /var/tmp/go-mod-cache /var/tmp/go-work \
    && chmod -R 0777 /var/tmp/go-build-cache /var/tmp/go-mod-cache /var/tmp/go-work

# Warm the Go build caches and prove the fixture compiles.
RUN cd /app && go test -vet=off ./... >/var/tmp/flume-buildtest.log 2>&1 || true

CMD ["/bin/bash"]
