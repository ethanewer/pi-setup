ARG UPSTREAM_SHA_PARENT=d4cffd848eb13d65f3caca5ef6da9a3fd25a2d6a
ARG UPSTREAM_SHA_FIX=c1d8045d86a9ef6b35b10c4106e67719247706e4
ARG GO_VERSION=1.26.8

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX
ARG GO_VERSION

ENV GOMODCACHE=/opt/go-cache \
    GOCACHE=/opt/go-cache \
    PATH=/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Base tooling. No C toolchain is required: the Go 1.26 module closure of
# this project builds with the pure compiler, verified during authoring
# (the full lib/fs test build succeeds on a base image without
# build-essential).
RUN apt-get update \
 && apt-get install -y --no-install-recommends git curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Go toolchain, pinned to an exact version (>= go.mod's `go 1.25.0`).
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -o /tmp/go.tgz \
 && tar -C /usr/local -xzf /tmp/go.tgz \
 && rm -f /tmp/go.tgz \
 && /usr/local/go/bin/go version

# Shared, world-writable module + build cache: every offline `go test` run
# (as root or as uid 1000 "ubuntu") lands here. The trial has no network.
RUN mkdir -p /opt/go-cache /opt/golden && chmod -R a+rwX /opt/go-cache /opt/golden

# Clone the REAL upstream tree pinned to the PARENT commit, shallow: a
# one-commit fetch means /app/src's object store contains exactly the
# parent commit and nothing else. The fix commit is never fetched here.
# (chmod in the same RUN so the tree is writable by the uid-1000 warm pass
# without duplicating any layer.)
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/syncthing/syncthing.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build" \
 && chmod -R a+rwX /app/src

# Pristine PRE-FIX tree for the verifier's "pre-fix concept" runs. Created
# before the warm pass; the golden test is planted below.
RUN cp -a /app/src /opt/prefix-src && chmod -R a+rwX /opt/prefix-src

# Warm the offline caches AS uid 1000, the same user a trial most often
# runs as: every entry Go creates in /opt/go-cache (module snapshots and
# compiled artifacts) is then owned by uid 1000 and reusable - and when the
# trial runs as root instead, root writes anywhere anyway.
USER ubuntu

RUN cd /app/src \
 && go test ./lib/ignore/ -run TestIssue3164 > /tmp/warm-ignore.log 2>&1; rc=$?; \
    tail -3 /tmp/warm-ignore.log; \
    if [ $rc -ne 0 ]; then echo "WARM ignore PASS FAILED (exit $rc)"; exit 1; fi \
 && go test ./lib/fs/ > /tmp/warm-fs.log 2>&1; rc=$?; \
    tail -3 /tmp/warm-fs.log; \
    if [ $rc -ne 0 ]; then echo "WARM fs PASS FAILED (exit $rc)"; exit 1; fi \
 && echo "caches warm (uid 1000)"

# Extract the project's own regression test for this bug (the test that the
# FIX commit adds to lib/ignore/ignore_test.go) through a THROWAWAY clone
# under /tmp that is deleted before any later layer, so the fix objects
# never enter /app/src and the golden bytes only ever live under /opt.
RUN git init -q /tmp/golden-clone \
 && cd /tmp/golden-clone \
 && git remote add origin https://github.com/syncthing/syncthing.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && git show ${UPSTREAM_SHA_FIX}:lib/ignore/ignore_test.go > /opt/golden/ignore_test.go \
 && test -s /opt/golden/ignore_test.go \
 && grep -q "TestIgnoreThroughSymlink" /opt/golden/ignore_test.go \
 && cd / \
 && rm -rf /tmp/golden-clone

# Plant the golden test into the pre-fix tree and confirm the FAIL
# direction IN THIS IMAGE with the pinned toolchain and warmed caches: the
# golden test must fail here and the failure must be the reported
# "too many levels of symbolic links" diagnostic. This also warms the
# pre-fix tree's build cache, so the verifier's pre-fix runs are instant.
RUN cp /opt/golden/ignore_test.go /opt/prefix-src/lib/ignore/ignore_test.go \
 && cd /opt/prefix-src \
 && go test ./lib/ignore/ -run TestIgnoreThroughSymlink -v > /tmp/prefix-fail.log 2>&1; rc=$?; \
    tail -4 /tmp/prefix-fail.log; \
    if [ $rc -eq 0 ]; then echo "BUG: golden test passed on the pre-fix tree"; exit 1; fi; \
    grep -q "too many levels of symbolic links" /tmp/prefix-fail.log \
      || { echo "BUG: no symlink diagnostic on pre-fix tree"; exit 1; } \
 && echo "FAIL direction confirmed inside this image"

USER root

# Belt: the fix commit must be unreachable from the trial clone, and the
# trial tree must sit exactly on the pinned parent commit.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "fix commit unreachable; HEAD = $(git rev-parse HEAD)"

# sha256 pins of the exact things the verifier executes (toolchain binaries
# and the golden test), so the verifier can detect substitution.
RUN mkdir -p /opt/pins \
 && sha256sum /usr/local/go/bin/go /usr/bin/git /opt/golden/ignore_test.go > /opt/pins/pins.sha256 \
 && chmod 555 /opt/pins /opt/golden \
 && chmod 444 /opt/pins/pins.sha256 /opt/golden/ignore_test.go \
 && sha256sum -c /opt/pins/pins.sha256 >/dev/null \
 && echo "toolchain + golden pinned"

COPY files/ /app/
WORKDIR /app
RUN chmod a+rwX /app

CMD ["/bin/bash"]