# bracket-dune: an upstream-clone debugging task on prometheus/prometheus.
#
# The image clones prometheus SHALLOW at the PARENT commit (the real upstream
# bug is present in the working tree), extracts the project's own regression
# test from the FIX commit at build time into /opt/golden/, and overlays that
# corrected matcher test into the tree exactly as the mining reproduction did
# (`git checkout <fix> -- model/labels/matcher_test.go`), so
# `go test -v ./model/labels -run TestPrefix` fails inside the image with the
# mined symptom. The fix commit is fetched only into a throwaway bare clone
# that is deleted, so it is never reachable from /app/src.
#
# Dependency pin from the verified issue: go 1.26.0. Module/compile caches are
# warmed at build time under world-writable paths so the trial (no network,
# possibly non-root) runs entirely offline.
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

ARG UPSTREAM_SHA=297523f69825b59e5e9afc121fd0263c4d0248e5
ARG FIX_SHA=f075de91d03d59f3d5996f1662eb9f0d6de7c40e

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# --- build toolchain ----------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential make git \
            ca-certificates curl patch \
 && rm -rf /var/lib/apt/lists/*

# --- go 1.26.0 toolchain (pinned) --------------------------------------------
RUN curl -sL -o /tmp/go.tgz https://go.dev/dl/go1.26.0.linux-amd64.tar.gz \
 && tar -C /opt -xzf /tmp/go.tgz \
 && rm -f /tmp/go.tgz \
 && /opt/go/bin/go version

# ---- working clone: buggy parent commit, fix commit unreachable -------------
RUN git clone --depth 1 https://github.com/prometheus/prometheus.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin 297523f69825b59e5e9afc121fd0263c4d0248e5 \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}"

# ---- extract the upstream regression test from the FIX commit ----------------
# Throwaway bare clone so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/prometheus/prometheus.git \
 && git fetch --depth 1 origin f075de91d03d59f3d5996f1662eb9f0d6de7c40e \
 && mkdir -p /opt/golden \
 && git show f075de91d03d59f3d5996f1662eb9f0d6de7c40e:model/labels/matcher_test.go \
      > /opt/golden/matcher_test.go \
 && test "$(sha256sum /opt/golden/matcher_test.go | cut -d' ' -f1)" \
      = "5103f31d0de8c8e4e3ac25c7f2378f17c70ac90e3895172ad1513735b1b7f9cd" \
 && cd / && rm -rf /tmp/fixsrc

# ---- overlay the corrected regression test into the working tree -------------
RUN cp /opt/golden/matcher_test.go /app/src/model/labels/matcher_test.go \
 && cd /app/src \
 && test "$(git diff --name-only)" = "model/labels/matcher_test.go" \
 && cmp -s /opt/golden/matcher_test.go model/labels/matcher_test.go \
 && ! git cat-file -e "${FIX_SHA}^{commit}"

# ---- go caches: warm at build, writable by any trial uid, no network needed --
ENV GOMODCACHE=/opt/go/pkg/mod \
    GOCACHE=/opt/go/gocache \
    PATH=/opt/go/bin:$PATH
RUN mkdir -p "$GOMODCACHE" "$GOCACHE" \
 && chmod -R a+rwX /app

# ---- warm the module build and fail closed if the bug is not present ---------
# (the warm-up runs as root; the chmod immediately after opens the caches for
# whichever uid the trial uses - the trial is offline, so it must never need
# to re-fetch, and it must be able to write new cache entries itself)
RUN cd /app/src \
 && ( go test -v ./model/labels -run TestPrefix > /tmp/warm.log 2>&1; \
      rc=$?; test "$rc" -ne 0 ) \
 && grep -q 'expected: ""' /tmp/warm.log \
 && grep -q 'actual  : "ABC"' /tmp/warm.log \
 && rm -f /tmp/warm.log \
 && chmod -R a+rwX "$GOMODCACHE" "$GOCACHE"

WORKDIR /app
CMD ["/bin/bash"]