# shroud-bulkhead: upstream-clone bug-fix task on aquasecurity/trivy
# (pnpm lockfile multi-document parsing). Parent commit ships the bug; the
# tree carries the project's own regression test for the bug, extracted from
# the FIX commit through a throwaway clone that is deleted here so the fix
# object never enters the shipped repository. The go 1.26.3 build cache is
# warmed so in-trial `go test` rebuilds are incremental.
#
# SHA pins (resolved with `git ls-remote` on 2026-09-13):
#   parent (bug present): a2777aed340e4bb11c6cea6d7cf5d4bf137587ec
#   fix  (upstream fix):  a10291be6f44a512977e887180faab3f3dd240c5
FROM bench-base:ubuntu-24.04
SHELL ["/bin/bash", "-c"]

ARG PARENT_SHA=a2777aed340e4bb11c6cea6d7cf5d4bf137587ec
ARG FIX_SHA=a10291be6f44a512977e887180faab3f3dd240c5

# uid-1000 git safety and build identity (the trial may run as uid 1000 and
# may legitimately create commits... it must not, but safe git is cheap).
RUN git config --system --add safe.directory '*' \
 && git config --system user.email build@localhost \
 && git config --system user.name build

# Go 1.26.3 toolchain, pinned (trivy's go.mod requires "go 1.26.3").
# Prebuilt tarball from actions/go-versions, same one the mining container used.
RUN curl -sSL -o /tmp/go.tgz https://github.com/actions/go-versions/releases/download/1.26.3-25533533231/go-1.26.3-linux-x64.tar.gz \
 && mkdir -p /opt/go \
 && tar -xzf /tmp/go.tgz -C /opt/go --strip-components=1 \
 && rm /tmp/go.tgz \
 && /opt/go/bin/go version \
 && test -x /opt/go/bin/go

# Everything go caches lives under /opt/builder (GOCACHE/GOPATH pinned), so a
# uid-1000 trial reads AND writes the same warm cache. GOMAXPROCS=1 keeps the
# single-CPU budget honest for the agent's own runs.
ENV HOME=/opt/builder \
    PATH=/opt/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    CGO_ENABLED=0 \
    GOEXPERIMENT=jsonv2 \
    GOMAXPROCS=1 \
    GOPATH=/opt/builder/go \
    GOCACHE=/opt/builder/.cache/go-build \
    GOENV=/opt/builder/.config/go/env

# Clone the parent commit ONLY (depth 1, single object), fail closed if the
# pin drifts upstream, assert the fix commit object is NOT reachable, overlay
# the golden regression test from a throwaway fix clone (deleted afterwards),
# store pristine parser sources for the verifier's pre-fix tree, and fix the
# ownership of the tree in the SAME layer that created it.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/aquasecurity/trivy.git \
 && git fetch --depth 1 origin "$PARENT_SHA" \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$PARENT_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && mkdir -p /app/.pristine/pnpm \
 && cp pkg/dependency/parser/nodejs/pnpm/parse.go /app/.pristine/pnpm/parse.go \
 && cp pkg/dependency/parser/nodejs/pnpm/types.go /app/.pristine/pnpm/types.go \
 && mkdir -p /tmp/fetch \
 && cd /tmp/fetch \
 && git init -q . \
 && git remote add origin https://github.com/aquasecurity/trivy.git \
 && git fetch --depth 1 origin "$FIX_SHA" \
 && git checkout --detach FETCH_HEAD \
 && P=/app/src/pkg/dependency/parser/nodejs/pnpm \
 && cp /tmp/fetch/pkg/dependency/parser/nodejs/pnpm/parse_test.go "$P/parse_test.go" \
 && cp /tmp/fetch/pkg/dependency/parser/nodejs/pnpm/parse_testcase.go "$P/parse_testcase.go" \
 && cp /tmp/fetch/pkg/dependency/parser/nodejs/pnpm/testdata/pnpm-lock_v9_multiple_documents.yaml "$P/testdata/pnpm-lock_v9_multiple_documents.yaml" \
 && cd / \
 && rm -rf /tmp/fetch \
 && chown -R 1000:1000 /app/src /app/.pristine \
 && echo "CLONE_PINNED_AND_GOLDEN_OVERLAID_OK"

# Warm the go build cache and PROVE the bug reproduces in this image: with the
# golden regression overlay in place, the module suite must FAIL at the parent
# commit on the multi-document case. Build and cache are one layer, chowned in
# the same layer so no ownership copy-on-write duplication occurs.
RUN cd /app/src \
 && go test -v -short ./pkg/dependency/parser/nodejs/pnpm/... > /tmp/pnpm_parent.log 2>&1; RC=$?; \
   echo "PARENT_MODULE_TEST_EXIT=$RC"; \
   tail -14 /tmp/pnpm_parent.log; \
   { test $RC -ne 0; } || { echo "EXPECTED_GOLDEN_FAILURE_DID_NOT_APPEAR" >&2; exit 1; }; \
   grep -q "FAIL: TestParse/v9_with_multiple_documents" /tmp/pnpm_parent.log \
     || { echo "EXPECTED_GOLDEN_FAILURE_DID_NOT_APPEAR" >&2; exit 1; }; \
   echo "REPRODUCED_AT_PARENT_OK"; \
   chown -R 1000:1000 /opt/builder; chmod -R a+rwX /opt/builder

# Prove the fix PASSES in this image too: overlay the upstream fix's two
# parser sources into a throwaway copy, run the module suite, delete the copy.
# The fix bytes leave the image at the end of this layer.
RUN mkdir -p /tmp/fetch \
 && cd /tmp/fetch \
 && git init -q . \
 && git remote add origin https://github.com/aquasecurity/trivy.git \
 && git fetch --depth 1 origin "$FIX_SHA" \
 && git checkout --detach FETCH_HEAD \
 && mkdir -p /tmp/fixcheck \
 && cp -r /app/src/. /tmp/fixcheck/ \
 && P=/tmp/fixcheck/pkg/dependency/parser/nodejs/pnpm \
 && cp /tmp/fetch/pkg/dependency/parser/nodejs/pnpm/parse.go "$P/parse.go" \
 && cp /tmp/fetch/pkg/dependency/parser/nodejs/pnpm/types.go "$P/types.go" \
 && cd / \
 && rm -rf /tmp/fetch \
 && cd /tmp/fixcheck \
 && go test -v -short ./pkg/dependency/parser/nodejs/pnpm/... > /tmp/pnpm_fix.log 2>&1; RC=$?; \
   tail -5 /tmp/pnpm_fix.log; \
   { test $RC -eq 0; } || { echo "FIX_PARITY_CHECK_FAILED" >&2; exit 1; }; \
   grep -q -- "--- PASS: TestParse/v9_with_multiple_documents" /tmp/pnpm_fix.log \
     || { echo "GOLDEN_CASE_DID_NOT_PASS_WITH_FIX" >&2; exit 1; }; \
   echo "FIX_PARITY_OK"; \
   cd / && rm -rf /tmp/fixcheck

WORKDIR /app
COPY files/ /app/
# /app must be writable by the trial user (uid 1000), who authors
# /app/repro.sh and /app/repro-fixture.yaml. Non-recursive on purpose: a
# recursive chmod over /app/src would copy the whole 157 MB tree into a new
# layer (the v4.2 image-size lesson). /app/src is already 1000-owned.
RUN chown 1000:1000 /app && chmod a+rwx /app && test -w /app && echo app-writable-ok