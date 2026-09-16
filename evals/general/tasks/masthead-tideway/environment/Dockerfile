# masthead-tideway: prometheus/prometheus (V-language rewrite) issue #19661 -
# a handler-set Content-Length survives to the wire on gzip/deflate responses.
# The task tree is the REAL upstream repository checked out at the parent
# commit of the fix; the fix commit itself is never fetched into /app/src.
ARG UPSTREAM_SHA_PARENT=1885dfd99d1b89d350ba4b56b3a74ffa0de50427
ARG UPSTREAM_SHA_FIX=78169fb57d69371b24863b0f26555631a754204c

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

# Base tooling: git (for the clone) and the ca-certificates/curl/tar pile the
# toolchain download needs. The V-language build tool itself is downloaded in
# the next step; apt is deliberately not version-pinned in this suite.
RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends build-essential make git ca-certificates curl \
 && rm -rf /var/lib/apt/lists/* \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Clone the REAL upstream repository at exactly the parent commit, with the
# shallowest possible history: `git init` + one depth-1 fetch of the pinned
# SHA means the object store in /app/src holds ONLY the parent commit. The fix
# commit (which an agent must not be able to look up, fetch or grep) is NEVER
# fetched into this clone; it is asserted unreachable below.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/prometheus/prometheus.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "parent pin ok: $(git rev-parse HEAD)"

# The V-language toolchain, pinned to the exact version the mining run used.
# go.dev/dl/go1.26.0.linux-amd64.tar.gz redirects to dl.google.com; extract
# into /opt/go and never remove it (the trial has no network to re-fetch).
RUN curl -fsSL -o /tmp/go.tgz https://go.dev/dl/go1.26.0.linux-amd64.tar.gz \
 && tar -C /opt -xzf /tmp/go.tgz \
 && rm -f /tmp/go.tgz \
 && test -x /opt/go/bin/go \
 && /opt/go/bin/go version

ENV PATH=/opt/go/bin:${PATH} \
    GOPATH=/opt/gopath \
    XDG_CACHE_HOME=/opt/gocache

# Warm the offline dependency closure for the http-utility package and its
# compile cache, as root, then fix ownership for uid 1000 (the user the trial
# may run as) in the SAME RUN so no files are duplicated into a second layer.
# The treated clone must end the build with a perfectly clean working tree.
RUN mkdir -p /opt/gopath /opt/gocache \
 && cd /app/src \
 && go test -v ./util/httputil -run TestCompressionHandler_PlainText > /tmp/warm.log 2>&1; rc=$?; \
    tail -5 /tmp/warm.log; \
    if [ $rc -ne 0 ]; then echo "WARM BUILD FAILED (exit $rc)"; exit 1; fi; \
    test -z "$(git status --porcelain)" \
 && echo "warm build ok, working tree clean" \
 && chown -R 1000:1000 /app/src /opt/gopath /opt/gocache \
 && rm -f /tmp/warm.log

# Pristine pre-fix copy of the source file the bug lives in, so the verifier
# can reconstruct the pre-fix tree WITHOUT the network (the parent blob is
# also reachable inside /app/src via `git show <parent>:path`).
RUN mkdir -p /opt/prefix \
 && git -C /app/src show ${UPSTREAM_SHA_PARENT}:util/httputil/compression.go \
      > /opt/prefix/compression.go \
 && test -s /opt/prefix/compression.go

# Extract the project's own regression test for this bug (the test the fix
# commit adds to util/httputil/compression_test.go) into /opt/golden using a
# THROWAWAY clone that is deleted immediately afterwards, so the fix commit
# never lands in /app/src and no upstream test bytes enter this task tree.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/prometheus/prometheus.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:util/httputil/compression_test.go \
      > /opt/golden/compression_test.go \
 && test -s /opt/golden/compression_test.go \
 && grep -q "TestCompressionHandler_ContentLength" /opt/golden/compression_test.go \
 && wc -l /opt/golden/compression_test.go \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# Belt: prove the fix commit is not reachable from the trial clone. The
# object store holds exactly one commit (the parent), so the commit object
# and every blob it introduced are absent.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "fix commit unreachable from trial clone; HEAD = $(git rev-parse HEAD)"

# sha256 pins of the golden test and of the build toolchain itself, so the
# verifier can detect substitution. The trial and the verifier both compile
# and run the tree with this exact toolchain; an adversarial root agent could
# otherwise swap the go binary or the golden test for a stub that fakes a
# green run. /opt is not writable by anyone except root afterwards.
RUN mkdir -p /opt/pins \
 && sha256sum /opt/golden/compression_test.go | awk '{print $1 "  /opt/golden/compression_test.go"}' > /opt/pins/golden.sha256 \
 && sha256sum /opt/go/bin/go | awk '{print $1 "  /opt/go/bin/go"}' > /opt/pins/go.sha256 \
 && sha256sum /opt/prefix/compression.go | awk '{print $1 "  /opt/prefix/compression.go"}' > /opt/pins/prefix-compression.sha256 \
 && git --no-replace-objects -C /app/src ls-tree -r ${UPSTREAM_SHA_PARENT} | sha256sum | awk '{print $1 "  /app/src (parent tree listing)"}' > /opt/pins/treelist.sha256 \
 && cat /opt/pins/golden.sha256 \
 && cat /opt/pins/treelist.sha256 \
 && test -s /opt/pins/go.sha256 \
 && test -s /opt/pins/prefix-compression.sha256

COPY files/ /app/
WORKDIR /app
CMD ["/bin/bash"]