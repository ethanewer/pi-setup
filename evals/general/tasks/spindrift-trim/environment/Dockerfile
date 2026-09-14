ARG UPSTREAM_SHA_PARENT=db309081bc5c137b2aa15701ef53f7f19788da25
ARG UPSTREAM_SHA_FIX=5c00df8afadd06cc5be530dde00fe6d9fa4a2e4a

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

# git (with curl for TLS + tar for archives) already ships in the base image.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Go 1.26.8 toolchain, pinned to the exact tarball (go.dev -> dl.google.com).
# Fail closed if the version string ever changes.
RUN curl -sL -o /tmp/go.tgz https://go.dev/dl/go1.26.8.linux-amd64.tar.gz \
 && tar -xzf /tmp/go.tgz -C /usr/local \
 && rm /tmp/go.tgz \
 && test "$(/usr/local/go/bin/go version)" = "go version go1.26.8 linux/amd64" \
 && echo "go 1.26.8 installed"

# Go module + build caches live under /opt/gocache, shared and writable by the
# build user, by a root trial and by a uid-1000 trial alike.
ENV PATH=/usr/local/go/bin:$PATH \
    GOMODCACHE=/opt/gocache/pkg/mod \
    GOCACHE=/opt/gocache/build \
    GOPATH=/opt/gocache \
    GOENV=/opt/gocache/env

# Clone the REAL upstream repository (gin-gonic/gin) at exactly the parent
# commit, shallowest possible history: `git init` + one depth-1 fetch of the
# pinned SHA means the object store in /app/src holds ONLY the parent commit.
# The fix commit (which an agent must not be able to look up or fetch) is
# NEVER fetched into this clone; it is asserted unreachable below.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/gin-gonic/gin.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "parent pin ok: $(git rev-parse HEAD)"

# Pristine PRE-FIX tree concept (no .git) at /opt/prefix-src: the same tree an
# agent ships, before any fix. The verifier runs the agent's own reproduction
# against this copy and requires it to FAIL, proving the symptom is real.
RUN mkdir -p /opt/prefix-src \
 && cd /app/src && git archive --format=tar HEAD | tar -x -C /opt/prefix-src \
 && test -f /opt/prefix-src/render/data.go \
 && ! grep -q "Content-Length" /opt/prefix-src/render/data.go \
 && echo "prefix-src is the pristine parent tree (no Content-Length in render/data.go)"

# Golden regression test: the project's own render/render_test.go as of the FIX
# commit (upstream added TestRenderDataContentLength and the Content-Length
# assertion in the same commit that fixed the bug). Extracted through a
# THROWAWAY clone that is deleted immediately afterwards, so the fix commit
# never lands in /app/src and no answer bytes enter the task tree.
RUN git init -q /tmp/fixclone \
 && cd /tmp/fixclone \
 && git remote add origin https://github.com/gin-gonic/gin.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_FIX}" \
 && mkdir -p /opt/golden \
 && cp render/render_test.go /opt/golden/render_test.go \
 && test -s /opt/golden/render_test.go \
 && grep -q "func TestRenderDataContentLength" /opt/golden/render_test.go \
 && grep -q 'Get("Content-Length")' /opt/golden/render_test.go \
 && cd / && rm -rf /tmp/fixclone \
 && echo "golden regression test extracted"

# Warm the module cache: compile the render package at the parent (downloads +
# sum-verifies all dependencies once, with network). The trial has no network,
# so this layer IS what makes every later run offline-capable. The chmod/chown
# run in the SAME layer that created the cache and the tree, so no bytes are
# ever duplicated into a later layer; the tree is handed to a root trial or a
# uid-1000 trial alike.
RUN cd /app/src \
 && go test github.com/gin-gonic/gin/render -test.run 'TestRenderString' > /tmp/warm.log 2>&1 \
 && grep -q '^ok' /tmp/warm.log \
 && rm -f /tmp/warm.log \
 && chmod -R a+rwX /opt/gocache \
 && chown -R 1000:1000 /app/src \
 && chmod -R a+rwX /app/src \
 && echo "warm build of render package at parent ok"

# Warm the cache for the PRE-FIX tree as well, so the verifier's pre-fix
# direction of the agent's reproduction only recompiles the agent's planted
# test file.
RUN cp -a /opt/prefix-src /tmp/prefixwarm \
 && cd /tmp/prefixwarm \
 && go test github.com/gin-gonic/gin/render -test.run 'TestRenderString' > /tmp/prefixwarm.log 2>&1 \
 && grep -q '^ok' /tmp/prefixwarm.log \
 && rm -rf /tmp/prefixwarm /tmp/prefixwarm.log \
 && chmod -R a+rwX /opt/gocache \
 && echo "pre-fix tree warm-compiled"

# Parent-direction confirmation in THIS image: the golden test, planted into a
# throwaway copy of the pristine parent tree, must FAIL with exactly the
# missing-Content-Length assertions. (The shipped /app/src stays pristine.)
RUN cp -a /app/src /tmp/parentcheck \
 && cp /opt/golden/render_test.go /tmp/parentcheck/render/render_test.go \
 && cd /tmp/parentcheck \
 && go test github.com/gin-gonic/gin/render -test.run 'TestRenderData' > /tmp/parentcheck.log 2>&1; \
    rc=$?; \
    if [ $rc -eq 0 ]; then echo "PARENT DIRECTION: golden tests unexpectedly passed"; exit 1; fi; \
    grep -q 'expected: "19"' /tmp/parentcheck.log \
 && grep -q 'expected: "100000"' /tmp/parentcheck.log \
 && echo "parent direction ok: golden tests fail on the pristine parent tree" \
 && rm -rf /tmp/parentcheck /tmp/parentcheck.log

# Fix-direction confirmation in THIS image: apply the upstream fix (the same
# authored patch the oracle applies) to a throwaway copy, plant the golden
# test, and require the golden tests to PASS.
RUN cat > /tmp/fix.patch <<'PATCH'
diff --git a/render/data.go b/render/data.go
index a653ea3..2c0ad5e 100644
--- a/render/data.go
+++ b/render/data.go
@@ -4,7 +4,10 @@
 
 package render
 
-import "net/http"
+import (
+	"net/http"
+	"strconv"
+)
 
 // Data contains ContentType and bytes data.
 type Data struct {
@@ -15,6 +18,9 @@ type Data struct {
 // Render (Data) writes data with custom ContentType.
 func (r Data) Render(w http.ResponseWriter) (err error) {
 	r.WriteContentType(w)
+	if len(r.Data) > 0 {
+		w.Header().Set("Content-Length", strconv.Itoa(len(r.Data)))
+	}
 	_, err = w.Write(r.Data)
 	return
 }
PATCH
RUN cp -a /app/src /tmp/fixcheck \
 && cd /tmp/fixcheck \
 && git apply --check /tmp/fix.patch \
 && git apply /tmp/fix.patch \
 && cp /opt/golden/render_test.go render/render_test.go \
 && go test github.com/gin-gonic/gin/render -test.run 'TestRenderData' > /tmp/fixcheck.log 2>&1; \
    rc=$?; \
    if [ $rc -ne 0 ]; then echo "FIX DIRECTION: golden tests did not pass on the fixed copy"; tail -20 /tmp/fixcheck.log; exit 1; fi; \
    grep -q '^ok' /tmp/fixcheck.log \
 && echo "fix direction ok: golden tests pass on the fixed copy" \
 && rm -rf /tmp/fixcheck /tmp/fixcheck.log /tmp/fix.patch

# Belt: prove the fix commit is not reachable from the trial clone. The object
# store holds exactly one commit (the parent), so the fix COMMIT object and
# every blob it introduced are absent.
RUN cd /app/src \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && if git cat-file -e "${UPSTREAM_SHA_FIX}^{commit}" 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && echo "fix commit unreachable from /app/src; HEAD = $(git rev-parse HEAD)"

# Integrity pins: sha256 of the go binary (toolchain substitution) and of the
# golden test. /opt/{golden,prefix-src,pins} end up read-only; the go caches
# and the tree are already world-writable from the layers that created them.
RUN mkdir -p /opt/pins \
 && sha256sum /usr/local/go/bin/go > /opt/pins/go.sha256 \
 && sha256sum /opt/golden/render_test.go > /opt/pins/golden.sha256 \
 && sha256sum -c /opt/pins/go.sha256 >/dev/null \
 && sha256sum -c /opt/pins/golden.sha256 >/dev/null \
 && chmod 555 /opt/pins /opt/golden /opt/prefix-src \
 && chmod 444 /opt/pins/*.sha256 /opt/golden/render_test.go \
 && find /opt/prefix-src -type f -exec chmod a+r {} + \
 && find /opt/prefix-src -type d -exec chmod a+rx {} + \
 && echo "integrity pins written; read-only assets finalised"

COPY files/ /app/
RUN chmod a+rwX /app && chmod 644 /app/README-BUILD.md && chown 1000:1000 /app/README-BUILD.md

WORKDIR /app

CMD ["/bin/bash"]