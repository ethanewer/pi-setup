# bracket-cable: gin-gonic/gin issue #4695 — Context.Copy() drops the Errors
# and Accepted lists, so a context snapshot behaves as if nothing had been
# recorded on the original (errors vanish, negotiated media types revert to
# empty). The fix (upstream commit 293ad7ed…) added the two copy blocks in
# context.go; the project's own regression test for it lives at the fix
# commit in context_test.go.
#
# The agent gets the REAL upstream repository at the PARENT commit (bug
# present). The fix commit is never fetched into /app/src: the clone is
# initialised empty and fetches ONLY the parent SHA, so no later commit —
# in particular not the fix, and not master — is reachable from the working
# clone. The regression test is extracted at build time into /opt/golden/
# from a throwaway clone that is deleted afterwards, keeping upstream bytes
# out of this task's tree.
#
# Toolchain: the "go" language toolchain go1.26.8 (go.dev tarball, linux
# amd64), plus make for the project's Makefile. gin's go.mod pins all
# third-party dependencies and go.sum pins their exact revisions; the first
# warm `go test` at build time downloads them all through the built-in gopkg
# manager and verifies them against go.sum, so the trial needs no network.
FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA=2e4d4f38962a6f15ae496d59b294f307eef95429
ARG FIX_SHA=293ad7edebb3ae30369288bd6416ca0d78474727

RUN apt-get update \
 && apt-get install -y --no-install-recommends make ca-certificates curl git \
 && rm -rf /var/lib/apt/lists/*

# ---- go1.26.8 toolchain (the "go" language toolchain, linux/amd64) ----------
RUN curl -fsSL -o /tmp/go.tgz https://go.dev/dl/go1.26.8.linux-amd64.tar.gz \
 && tar -xzf /tmp/go.tgz -C /usr/local \
 && rm /tmp/go.tgz \
 && test -x /usr/local/go/bin/go \
 && /usr/local/go/bin/go version | grep -q 'go1.26.8'

ENV PATH=/usr/local/go/bin:$PATH \
    GOPROXY=https://proxy.golang.org \
    GO111MODULE=on

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone at the buggy PARENT commit; fix commit unreachable ------
RUN git init /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/gin-gonic/gin.git \
 && git fetch --depth 1 origin 2e4d4f38962a6f15ae496d59b294f307eef95429 \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && test -f /app/src/context.go \
 && test -f /app/src/context_test.go \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src'

# ---- extract the upstream regression test from the FIX commit ---------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/gin-gonic/gin.git \
 && git fetch --depth 1 origin 293ad7edebb3ae30369288bd6416ca0d78474727 \
 && mkdir -p /opt/golden \
 && git show 293ad7edebb3ae30369288bd6416ca0d78474727:context_test.go \
      > /opt/golden/context_test.go \
 && test -s /opt/golden/context_test.go \
 && grep -q 'func TestContextCopyCopiesErrors' /opt/golden/context_test.go \
 && grep -q 'func TestContextCopyCopiesAccepted' /opt/golden/context_test.go \
 && grep -q 'func TestContextCopyNilErrorsAndAccepted' /opt/golden/context_test.go \
 && cd / && rm -rf /tmp/fixsrc

# ---- warm every cache at build time (the trial has no network) ---------------
# Downloads all go.mod dependencies via the built-in gopkg manager, verifies
# them against go.sum, and compiles the whole gin package + test files. The
# result lives in /root/.cache/go-build and /root/go/pkg and is reused by the
# trial, so even a cold agent shell is fast.
RUN cd /app/src \
 && go test -v github.com/gin-gonic/gin -test.run 'TestContextCopy$' > /tmp/warm1.log 2>&1 \
 && grep -q -- '--- PASS: TestContextCopy' /tmp/warm1.log \
 && ! grep -q -- '--- FAIL' /tmp/warm1.log \
 && go test -v github.com/gin-gonic/gin -test.run 'TestContext' > /tmp/warm2.log 2>&1 \
 && ! grep -q -- '--- FAIL' /tmp/warm2.log \
 && grep -q '^ok' /tmp/warm2.log \
 && rm -f /tmp/warm1.log /tmp/warm2.log

# ---- probe shipped with the trial -------------------------------------------------
WORKDIR /app
COPY files/ /app/

# Agents work in /app; the golden test extracted from the fix commit must stay
# pristine (the verifier additionally re-checks its sha256 before running it).
RUN chmod -R a+rwX /app \
 && chmod 555 /opt/golden \
 && chmod 444 /opt/golden/context_test.go

CMD ["/bin/bash"]