# cistern-cleat: an upstream bug-fix task on the real gin web framework.
#
# The image clones gin-gonic/gin SHALLOW at the PARENT commit (the real
# upstream bug is present in the working tree) and extracts the project's own
# regression tests for the bug from the FIX commit at build time into
# /opt/golden/ (upstream bytes never enter this repository). The fix commit is
# a descendant of the parent, so it is NOT reachable from the depth-1 clone the
# agent works on; the extraction uses a throwaway bare clone that is deleted.
#
# Toolchain: gin's go.mod declares "go 1.24.0" and its tests run under the new
# go command (`go test`). apt's golang-go is far too old, so the official
# go1.24.0 linux-amd64 tarball is downloaded once at build time (go.dev/dl is
# reachable at build time; there is no network in the trial) and verified by
# sha256 before extraction.
FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA=915e4c90d28ec4cffc6eb146e208ab5a65eac772
ARG FIX_SHA=9914178584e42458ff7d23891463a880f58c9d86
ARG GO_SHA256=dea9ca38a0b852a74e81c26134671af7c0fbe65d81b0dc1c5bfe22cf7d4c8858

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- Go 1.24.0 toolchain ------------------------------------------------------
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends ca-certificates curl \
 && curl -fsSL --retry 3 -o /tmp/go.tgz https://go.dev/dl/go1.24.0.linux-amd64.tar.gz \
 && echo "$GO_SHA256  /tmp/go.tgz" | sha256sum -c - \
 && mkdir -p /opt/go \
 && tar -xzf /tmp/go.tgz -C /opt/go --strip-components=1 \
 && ln -s /opt/go/bin/go /usr/local/bin/go \
 && rm -f /tmp/go.tgz \
 && go version

# ---- working clone: buggy parent commit, fix commit unreachable --------------
# A depth-1 clone of master cannot contain the parent SHA, so fetch the parent
# by SHA, detach onto it and fail closed if upstream ever moves it.
RUN git clone --depth 1 https://github.com/gin-gonic/gin.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin $UPSTREAM_SHA \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src'

# ---- extract the upstream regression tests from the FIX commit ----------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/gin-gonic/gin.git \
 && git fetch --depth 1 origin $FIX_SHA \
 && mkdir -p /opt/golden \
 && git show $FIX_SHA:context_test.go > /opt/golden/context_test.go \
 && test -s /opt/golden/context_test.go \
 && grep -q "TestContextClientIPWithMultipleHeaders" /opt/golden/context_test.go \
 && grep -q "TestContextClientIPWithSingleHeader" /opt/golden/context_test.go \
 && cd / && rm -rf /tmp/fixsrc

# ---- warm module + build caches as the trial uid (1000) so go is offline -----
RUN mkdir -p /opt/gomodcache /opt/gocache \
 && chmod 777 /opt/gomodcache /opt/gocache /app/src

ENV GO111MODULE=on \
    GOMODCACHE=/opt/gomodcache \
    GOCACHE=/opt/gocache \
    GOTELEMETRYDIR=/opt/gomodcache \
    HOME=/home/ubuntu

USER ubuntu
WORKDIR /app/src
# Compile the whole package once and download every declared module, so both
# caches are warm inside the image; the trial must not touch the network.
RUN go mod download \
 && go test -v github.com/gin-gonic/gin -test.run "TestNoSuchTestCompileOnly"

USER root
RUN chmod -R a+rwX /app/src /opt/gomodcache /opt/gocache

WORKDIR /app
COPY files/ /app/
RUN chmod -R a+rwX /app

CMD ["/bin/bash"]