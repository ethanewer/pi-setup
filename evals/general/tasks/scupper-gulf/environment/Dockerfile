# scupper-gulf: syncthing #10709 - zero-count block requests kill the connection.
#
# The image clones REAL upstream syncthing SHALLOW at the PARENT commit (the
# real bug, upstream issue #10709, is present in the working tree) and
# extracts the project's own regression tests for the bug from the FIX commit
# at build time into /opt/golden/ (upstream bytes never enter this
# repository). The fix commit is never fetched into the working clone, so it
# is unreachable from /app/src; the golden extraction uses a throwaway clone
# under /tmp that is deleted afterwards.
#
# Everything that needs the network happens here at build time: apt, the
# pinned Go toolchain, the clone, the module download cache, and one warm
# full-suite compile as uid 1000. At trial time the tree, the toolchain cache
# and the compile cache are complete, so `go test` runs fully offline.

# Go toolchain stage: the official golang:1.26.3 image carries the exact
# go1.26.3 distribution this task pins (dl.go.dev has been flapping between
# resolvable and NXDOMAIN), digest-pinned so a re-tag of the upstream image
# cannot silently change what is built. Only /usr/local/go (bin/go,
# gofmt, api/, lib/, pkg/) is copied into the final image.
FROM golang:1.26.3@sha256:2d6c80227255c3112a4d08e67ba98e58efd3846daf15d9d7d4c389565d881b1a AS gotoolchain

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA=3ec73403c1fece449d4776a8d62b159440455d80
ARG FIX_SHA=6be1ff84802810ebf6ab5a5169f865333607a8a5

ENV DEBIAN_FRONTEND=noninteractive

# ---- base tooling -----------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

# ---- pinned Go toolchain (go1.26.3, modular distribution; the tree's go.mod
#      requires go >= 1.25) ---------------------------------------------------
COPY --from=gotoolchain /usr/local/go /usr/local/go
RUN /usr/local/go/bin/go version \
 && test -d /usr/local/go/api \
 && test -d /usr/local/go/pkg \
 && test -x /usr/local/go/bin/gofmt

ENV PATH=/usr/local/go/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin \
    GOPATH=/var/go \
    GOMODCACHE=/var/go/pkg/mod \
    GOCACHE=/var/go/.cache \
    GOFLAGS="-mod=mod" \
    GOSUMDB=off \
    GOPROXY=https://proxy.golang.org

# ---- git plumbing, and a writable user for the trial (bench-base already
#      ships `ubuntu`, uid/gid 1000) ------------------------------------------
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build" \
 && mkdir -p /var/go /opt/golden /app \
 && chown 1000:1000 /var/go /opt/golden /app

# ---- working clone: buggy parent commit, fix commit truly absent ---------
# One shallow fetch of the parent SHA into a fresh repo: the fix commit is
# never fetched, so it cannot exist in /app/src/.git even though the build
# has network. The checkout materialises the parent tree's blobs on demand.
# After that, the promisor/partial-clone plumbing is removed so no later git
# read can on-demand-fetch the fix commit from GitHub. Fail closed if
# upstream moves. (The su subshell does not see build ARGs, so the SHAs are
# spelled out inside it; the ARG assertions run outside as root.)
RUN su ubuntu -s /bin/bash -c 'set -e; \
  git init -q /app/src \
  && cd /app/src \
  && git remote add origin https://github.com/syncthing/syncthing.git \
  && git fetch --depth 1 --filter=blob:none origin 3ec73403c1fece449d4776a8d62b159440455d80 \
  && git checkout --detach FETCH_HEAD \
  && git clean -fd \
  && git config --local remote.origin.promisor false \
  && git config --local --unset remote.origin.partialclonefilter \
  && git config --local --unset extensions.partialClone || true' \
 && GIT_NO_LAZY_FETCH=1 test "$(git -C /app/src rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ( GIT_NO_LAZY_FETCH=1 git -C /app/src cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null && exit 1 || true ) \
 && GIT_NO_LAZY_FETCH=1 test "$(git -C /app/src rev-list --count HEAD)" = "1"

# ---- extract the project's own regression test from the FIX commit ----------
# Throwaway clone under /tmp, deleted immediately afterwards, so the fix
# commit and its test bytes never exist inside /app/src/.git nor get shipped
# in the trial image beyond /opt/golden/protocol_test.go.
RUN git init -q /tmp/goldfix \
 && cd /tmp/goldfix \
 && git remote add origin https://github.com/syncthing/syncthing.git \
 && git fetch --depth 1 origin 6be1ff84802810ebf6ab5a5169f865333607a8a5 \
 && git show 6be1ff84802810ebf6ab5a5169f865333607a8a5:lib/protocol/protocol_test.go \
      > /opt/golden/protocol_test.go \
 && test -s /opt/golden/protocol_test.go \
 && grep -q "func TestRequestZeroSize" /opt/golden/protocol_test.go \
 && echo "d5706f8387aa8c15a678ed6721d1ebe254feeeea8f4f0bab8dae3a5ea6ad8840  /opt/golden/protocol_test.go" | sha256sum -c - \
 && cd / \
 && rm -rf /tmp/goldfix

# Belt: with the promisor disabled and lazy fetch off, cat-file can only
# answer from objects in the store, so this check cannot fetch the fix commit
# from GitHub even though the build has network. (On a partial clone, git
# cat-file -e <unknown sha> starts an on-demand fetch from the promisor
# remote by default; the first version of this build silently pulled the fix
# commit that way.)
RUN ( GIT_NO_LAZY_FETCH=1 su ubuntu -s /bin/bash -c 'cd /app/src && git cat-file -e 6be1ff84802810ebf6ab5a5169f865333607a8a5^{commit}' 2>/dev/null && exit 1 || true ) \
 && GIT_NO_LAZY_FETCH=1 test "$(git -C /app/src rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && GIT_NO_LAZY_FETCH=1 test "$(git -C /app/src rev-list --count HEAD)" = "1"

# ---- warm every cache the trial needs, as uid 1000 --------------------------
# Downloads every go.mod dependency and compiles the whole lib/protocol test
# package plus its transitive deps, so the trial compiles/reruns offline. The
# suite is fully green here (46 tests) as a build-time canary.
RUN su ubuntu -s /bin/bash -c 'export PATH=/usr/local/go/bin:$PATH; cd /app/src && go mod download all'
RUN su ubuntu -s /bin/bash -c 'export PATH=/usr/local/go/bin:$PATH; cd /app/src && go test ./lib/protocol/ -v'

# Trial-time: no network. Any accidental fetch fails fast instead of hanging.
ENV GOPROXY=off

# Nothing in /app yet; keep the COPY so the layout is uniform with the other
# tasks. /app/src stays owned by uid 1000 from the start (no layer duplicating
# no chown of a big tree later: the checkout and all go caches were made by uid 1000 from the start).
COPY files/ /app/

WORKDIR /app
CMD ["/bin/bash"]