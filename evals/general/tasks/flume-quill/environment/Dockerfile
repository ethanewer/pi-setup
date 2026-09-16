# flume-quill: a Go repository pinned to an obsolete major of urfave/cli that
# the agent must upgrade to v3 with a full call-site migration.
#
# The trial container has no network. Everything the upgrade needs (the Go
# toolchain, the v1 fixture's dependency graph, and the v3.11.0 target graph)
# is baked into this image; `go get`/`go mod tidy` work offline from
# /go/pkg/mod, which generate_repo.sh pre-populates.
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq && \
    apt-get install -y -qq golang-go git ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# The fixture repository is built as root and the harness may run the trial as
# uid 1000; git refuses to operate on a repo owned by another user, so record a
# system-wide exception (also needed for any repo the agent itself creates).
# A committer identity is required for the build-time commits in the generator.
RUN git config --system --add safe.directory '*' && \
    git config --system user.email "build@localhost" && \
    git config --system user.name "build"

# Shared Go environment: a fixed module cache and build cache so whatever user
# the trial runs as can build and test. Offline resolution is enforced at the
# end of the file.
ENV GOPATH=/go \
    GOMODCACHE=/go/pkg/mod \
    GOCACHE=/go/.cache \
    GOFLAGS=-mod=mod \
    GOSUMDB=off

WORKDIR /app
COPY files/ /app/

# Build the fixture repository (writes /app/flume with git history, proves the
# suite green) and pre-populate the module cache with the v3.11.0 target graph.
# Network is available only at build time.
RUN bash /app/generate_repo.sh

# Trial time: no network. Fail fast on any uncached module lookup.
ENV GOPROXY=off

# The harness may run the trial as a non-root user; make the cache and the
# repository usable by anyone.
RUN chmod -R a+rwX /go /app/flume && \
    rm -f /app/generate_repo.sh

CMD ["/bin/bash"]
