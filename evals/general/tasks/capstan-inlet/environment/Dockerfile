ARG UPSTREAM_SHA_PARENT=f06520353fc632e69eaf9d669ecdd785e770305a
ARG UPSTREAM_SHA_FIX=3c6a1a2aca33893f231412a34d3dfddc4f64b456

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

# Go toolchain lock, dependency caches and the test-runner mode the whole
# task family uses (verified during mining). GOMODCACHE/GOCACHE are fixed
# paths under /opt so the no-network trial finds a warm cache regardless of
# which uid it runs as; both are made world-writable further down.
ENV PATH=/opt/go/bin:$PATH \
    GOMODCACHE=/opt/gomodcache \
    GOCACHE=/opt/gocache \
    GOEXPERIMENT=jsonv2 \
    CGO_ENABLED=0

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git \
 && rm -rf /var/lib/apt/lists/*

# Go 1.26.3, the exact toolchain `go.mod` requires (`go 1.26.3`). This is the
# same prebuilt binary the trivy CI line for this Go line installs
# (actions/go-versions, tag 1.26.3-25533533231).
RUN curl -sSL -o /tmp/go.tgz \
      https://github.com/actions/go-versions/releases/download/1.26.3-25533533231/go-1.26.3-linux-x64.tar.gz \
 && mkdir -p /opt/go \
 && tar -xzf /tmp/go.tgz -C /opt/go --strip-components=1 \
 && rm -f /tmp/go.tgz \
 && /opt/go/bin/go version

# Clone the REAL upstream repository at exactly the parent commit, with the
# shallowest possible history: `git init` + one depth-1 fetch of the pinned
# SHA means the object store in /app/src holds ONLY the parent commit. The
# fix commit (which an agent must not be able to look up or fetch) is never
# fetched into this clone.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/aquasecurity/trivy.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Extract the project's own regression test for this bug (core_deps'
# parse_test.go plus its two new fixtures, exactly as they exist at the fix
# commit) into /opt/golden using a THROWAWAY clone that is deleted immediately
# afterwards, so upstream test bytes never land in this task tree and the fix
# commit never lands in /app/src.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/aquasecurity/trivy.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:pkg/dependency/parser/dotnet/core_deps/parse_test.go > /opt/golden/parse_test.go \
 && git show ${UPSTREAM_SHA_FIX}:pkg/dependency/parser/dotnet/core_deps/testdata/ambiguous-root.deps.json > /opt/golden/ambiguous-root.deps.json \
 && git show ${UPSTREAM_SHA_FIX}:pkg/dependency/parser/dotnet/core_deps/testdata/multi-project.deps.json > /opt/golden/multi-project.deps.json \
 && test -s /opt/golden/parse_test.go \
 && grep -q "multi-project solution" /opt/golden/parse_test.go \
 && grep -q "ambiguous root" /opt/golden/parse_test.go \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# Belt: prove the fix commit is not reachable from the trial clone.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}"

# The image is built as root; the trial may run as root or as uid 1000
# (user `ubuntu` already exists in the base image). Make the tree and the Go
# caches writable by whoever runs, and WARM every cache the trial needs AS
# uid 1000, so writable bookkeeping files are owned by the trial user from
# the start. The warm pass downloads every go.sum-pinned dependency and
# compiles the core_deps parser package plus its test; the trial has no
# network, so this layer IS the warm cache. (The tree's own tests all pass
# at the parent commit; only the regression cases added by the fix commit
# expose the bug.)
RUN chmod -R a+rwX /app/src \
 && mkdir -p /opt/gomodcache /opt/gocache \
 && chmod -R a+rwX /opt/gomodcache /opt/gocache \
 && chown -R 1000:1000 /app/src 2>/dev/null || true
RUN su -s /bin/bash ubuntu -c 'cd /app/src && export PATH=/opt/go/bin:$PATH && \
    export GOMODCACHE=/opt/gomodcache GOCACHE=/opt/gocache GOEXPERIMENT=jsonv2 CGO_ENABLED=0 && \
    go test -short ./pkg/dependency/parser/dotnet/core_deps/ > /tmp/warm.log 2>&1'; rc=$?; \
    tail -3 /tmp/warm.log; \
    if [ $rc -ne 0 ]; then echo "WARM BUILD FAILED (exit $rc)"; exit $rc; fi; \
    grep -c "ok   " /tmp/warm.log | xargs -I{} echo "warm package results: {} line(s)"; \
    rm -f /tmp/warm.log

WORKDIR /app
COPY files/ /app/
RUN chmod -R a+rwX /app && chmod +x /app/reproduce.sh

CMD ["/bin/bash"]