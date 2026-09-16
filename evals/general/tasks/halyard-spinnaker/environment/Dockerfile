# halyard-spinnaker — gohugoio/hugo, upstream issue #7528
#
# The tree is pinned at the parent of the upstream fix:
#   parent: 8ee6de6d96a64395d27416d4f2ad7d172a2686d0 (Dec 2021, hugo 0.91.0-DEV)
#   fix:    5758c370eac6c4460cd6bb34d4475c8d347585f6 (Allow for return partials
#           with falsy arguments, PR #9298)
# The fix commit is NEVER fetched into /app/src; its regression test (the
# function TestPartialWithZeroedArgs in hugolib/template_test.go) is
# extracted into /opt/golden through a throwaway clone under /tmp that is
# deleted immediately afterwards.
ARG UPSTREAM_SHA_PARENT=8ee6de6d96a64395d27416d4f2ad7d172a2686d0
ARG UPSTREAM_SHA_FIX=5758c370eac6c4460cd6bb34d4475c8d347585f6
ARG GO_VERSION=1.27.1

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX
ARG GO_VERSION

# Go 1.27.1 is the exact toolchain the mining run used (dependency pin from
# the slot entry). The Hugo tree of this era carries its own go.mod/go.sum
# module pins; the go toolchain resolves them through GOPROXY, so the proxy
# must be reachable at build time (it is) and every dependency must be baked
# into the image before the trial.
ENV PATH=/usr/local/go/bin:$PATH \
    GOPROXY=https://proxy.golang.org \
    GOCACHE=/opt/gocache \
    GOMODCACHE=/opt/gomodcache

WORKDIR /app

RUN apt-get update \
 && apt-get install -y --no-install-recommends git curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/go.tgz https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz \
 && tar -C /usr/local -xzf /tmp/go.tgz \
 && rm -f /tmp/go.tgz \
 && /usr/local/go/bin/go version

# Clone the REAL upstream repository at exactly the pinned parent commit
# with the shallowest possible history (one depth-1 fetch of the SHA), so
# the object store in /app/src holds ONLY the parent commit.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/gohugoio/hugo.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# The trial may run as root or as uid 1000. Everything the agent must edit
# or build (the tree, the go caches) is owned by uid 1000 and world
# writable; the toolchain in /usr/local/go stays root-owned read-only.
RUN mkdir -p /opt/gocache /opt/gomodcache \
 && chown -R 1000:1000 /app/src /opt/gocache /opt/gomodcache \
 && chmod -R a+rwX /app/src /opt/gocache /opt/gomodcache

# Warm every cache the trial needs AS the uid-1000 user, exactly as the
# trial will run: fetch all module sources into /opt/gomodcache and compile
# the whole project (the hugo CLI binary) plus the hugolib test harness
# into /opt/gocache. The trial has no network; this layer IS the warm cache.
RUN su -s /bin/bash ubuntu -c 'export PATH=/usr/local/go/bin:$PATH GOCACHE=/opt/gocache GOMODCACHE=/opt/gomodcache GOPROXY=https://proxy.golang.org && cd /app/src && go build -o /tmp/hugo-warm > /tmp/warm1.log 2>&1'; rc=$?; \
    tail -3 /tmp/warm1.log; \
    if [ $rc -ne 0 ]; then echo "WARM BUILD FAILED (exit $rc)"; exit $rc; fi; \
    test -x /tmp/hugo-warm || { echo "no hugo binary"; exit 1; }
RUN su -s /bin/bash ubuntu -c 'export PATH=/usr/local/go/bin:$PATH GOCACHE=/opt/gocache GOMODCACHE=/opt/gomodcache GOPROXY=https://proxy.golang.org && cd /app/src && go test -vet=off ./hugolib -run TestPartialCached > /tmp/warm2.log 2>&1'; rc=$?; \
    tail -2 /tmp/warm2.log; \
    if [ $rc -ne 0 ]; then echo "WARM TEST-BUILD FAILED (exit $rc)"; exit $rc; fi

# Bake a pristine PRE-FIX hugo binary at /opt/prefix/hugo. The verifier runs
# the agent's own reproduction against this binary and requires it to FAIL,
# proving both that the symptom is real and that the reproduction targets
# it.
RUN mkdir -p /opt/prefix \
 && cp /tmp/hugo-warm /opt/prefix/hugo \
 && rm -f /tmp/hugo-warm \
 && chmod 755 /opt/prefix/hugo \
 && /opt/prefix/hugo version | head -1

# Extract the project's own regression test (the fix commit replaces the old
# "Zero argument" subtest with TestPartialWithZeroedArgs in
# hugolib/template_test.go) into /opt/golden using a THROWAWAY clone that is
# deleted immediately afterwards, so the fix object never enters /app/src.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/gohugoio/hugo.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:hugolib/template_test.go > /opt/golden/template_test.go \
 && test -s /opt/golden/template_test.go \
 && grep -q "TestPartialWithZeroedArgs" /opt/golden/template_test.go \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# Parent-direction reproduction inside THIS image: with the golden
# regression test planted into the parent tree, the exact `go test`
# invocation the verifier will use must FAIL on the parent sources with the
# bug's signature. Plant, run, require the failure, restore byte-for-byte.
RUN cp /opt/golden/template_test.go /app/src/hugolib/template_test.go \
 && cd /app/src \
 && go test -vet=off ./hugolib -run TestPartialWithZeroedArgs -v > /tmp/parentdir.log 2>&1; rc=$?; \
    grep -E "RUN  TestPartialWithZeroedArgs|needs a non-zero argument" /tmp/parentdir.log | head -3; \
    if [ $rc -eq 0 ]; then echo "BUG DID NOT REPRODUCE AT PARENT (test passed)"; exit 1; fi; \
    grep -q "needs a non-zero argument" /tmp/parentdir.log || { echo "wrong failure signature"; exit 1; } \
 && git checkout -q -- hugolib/template_test.go \
 && test -z "$(git status --porcelain)"

# Belt: the fix commit must not be reachable from the trial clone; HEAD must
# still be the pinned parent; the tree must be clean.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && test -z "$(git status --porcelain)" \
 && echo "fix commit unreachable; HEAD = $(git rev-parse HEAD); tree clean"

# Lock down the trust anchors: the go binary, git, the golden test and the
# pre-fix binary are sha256-pinned so the verifier can detect substitution.
RUN mkdir -p /opt/pins \
 && sha256sum /usr/local/go/bin/go /usr/bin/git /opt/golden/template_test.go /opt/prefix/hugo > /opt/pins/anchors.sha256 \
 && chmod 555 /opt/pins /opt/golden /opt/prefix \
 && chmod 444 /opt/pins/anchors.sha256 /opt/golden/template_test.go \
 && chmod 755 /opt/prefix/hugo \
 && cd / && sha256sum -c /opt/pins/anchors.sha256 >/dev/null \
 && chown -R 1000:1000 /app/src /opt/gocache /opt/gomodcache \
 && chmod -R a+rwX /app/src /opt/gocache /opt/gomodcache \
 && rm -f /tmp/warm1.log /tmp/warm2.log /tmp/parentdir.log

COPY files/ /app/
RUN chmod a+rwX /app

CMD ["/bin/bash"]