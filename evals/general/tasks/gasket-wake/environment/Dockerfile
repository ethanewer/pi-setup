# gasket-wake: gin-gonic/gin issue #4535 - the case-insensitive fixed-path
# lookup can panic with "invalid node type" and kill the server when the
# routing tree has a node with both static children and a wildcard (param or
# catch-all) child.
#
# The image ships the REAL upstream repository at the PARENT commit (the bug
# is present in the working tree). The fix commit is never fetched into
# /app/src: the clone is initialised empty and fetches ONLY the parent SHA,
# so no later commit - in particular not the fix - is reachable from the
# working clone. The project's own regression tests for the bug (added at the
# fix commit in tree_test.go) are extracted at build time into /opt/golden/
# from a throwaway bare clone that is deleted afterwards, so upstream bytes
# never enter this task's tree. The pristine (buggy) tree.go is copied to
# /opt/golden/ as well: the verifier restores it over a throwaway copy of the
# repaired tree to prove the agent's own reproduction actually fails on the
# pre-fix code.
#
# Toolchain: the "go" language toolchain go1.26.8 (go.dev tarball, linux
# amd64, sha256-pinned below), plus make for the project's Makefile. gin's
# go.mod pins all third-party dependencies; the first warm `go test` at build
# time downloads them all through the built-in gopkg manager and verifies
# them against go.sum, so the trial runs fully offline.
FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA=fb2583442c4d9bccb75e6d26f1aa6e7c01950db6
ARG FIX_SHA=472d086af2acd924cb4b9d7be0525f7d790f69bc
ARG GO_TGZ_SHA256=d0f743b33e8d8945e6b1f432edd15785c70507121d6e2a723b21285eddf8b57b

RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends make ca-certificates curl git \
 && rm -rf /var/lib/apt/lists/*

# ---- go1.26.8 toolchain (the "go" language toolchain, linux/amd64) ----------
RUN curl -fsSL --retry 3 -o /tmp/go.tgz https://go.dev/dl/go1.26.8.linux-amd64.tar.gz \
 && echo "$GO_TGZ_SHA256  /tmp/go.tgz" | sha256sum -c - \
 && tar -xzf /tmp/go.tgz -C /usr/local \
 && rm /tmp/go.tgz \
 && test -x /usr/local/go/bin/go \
 && test "$(/usr/local/go/bin/go version)" = "go version go1.26.8 linux/amd64"

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
 && git fetch --depth 1 origin $UPSTREAM_SHA \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && test -f /app/src/tree.go \
 && test -f /app/src/tree_test.go \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src' \
 && mkdir -p /opt/golden \
 && cp /app/src/tree.go /opt/golden/tree.go.parent

# ---- extract the upstream regression test from the FIX commit ---------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/gin-gonic/gin.git \
 && git fetch --depth 1 origin $FIX_SHA \
 && git show $FIX_SHA:tree_test.go > /opt/golden/tree_test.go \
 && test -s /opt/golden/tree_test.go \
 && grep -q 'func TestTreeFindCaseInsensitivePathWithMultipleChildrenAndWildcard' /opt/golden/tree_test.go \
 && grep -q 'func TestTreeFindCaseInsensitivePathWildcardParamAndStaticChild' /opt/golden/tree_test.go \
 && cd / && rm -rf /tmp/fixsrc

# ---- warm every cache at build time (the trial has no network) ---------------
# Downloads all go.mod dependencies via the built-in gopkg manager, verifies
# them against go.sum, and compiles the whole gin package, binding and render
# plus their test files. The result lives in /root/.cache/go-build and
# /root/go/pkg and is reused by the trial, so even a cold agent shell is
# fast. The full gin suite run proves the pinned parent tree is green.
RUN cd /app/src \
 && go test -v github.com/gin-gonic/gin -test.run 'TestNoSuchTestCompileOnly' > /tmp/warm1.log 2>&1 \
 && grep -q 'no tests to run' /tmp/warm1.log \
 && go test -v github.com/gin-gonic/gin/binding -test.run 'TestNoSuchTestCompileOnly' >> /tmp/warm1.log 2>&1 \
 && go test -v github.com/gin-gonic/gin/render -test.run 'TestNoSuchTestCompileOnly' >> /tmp/warm1.log 2>&1 \
 && go test -v github.com/gin-gonic/gin > /tmp/warm2.log 2>&1 \
 && ! grep -q '^--- FAIL' /tmp/warm2.log \
 && grep -q '^ok' /tmp/warm2.log \
 && rm -f /tmp/warm1.log /tmp/warm2.log

# ---- fail-closed: the image must carry the mined failing state --------------
# The two upstream regression tests, overlaid on a throwaway copy of the
# tree, must PANIC exactly like the mining run: 'panic: invalid node type'
# in findCaseInsensitivePathRec. If upstream ever moves the pin, or the
# dependency versions no longer trigger the bug, this build fails.
RUN rm -rf /tmp/smoke \
 && cp -a /app/src /tmp/smoke \
 && cp /opt/golden/tree_test.go /tmp/smoke/tree_test.go \
 && (cd /tmp/smoke && go test -v github.com/gin-gonic/gin \
       -test.run 'TestTreeFindCaseInsensitivePath(WithMultipleChildrenAndWildcard|WildcardParamAndStaticChild)' \
       > /tmp/smoke.log 2>&1; test $? -ne 0) \
 && grep -q 'panic: invalid node type' /tmp/smoke.log \
 && rm -rf /tmp/smoke /tmp/smoke.log

# ---- pin the pristine tree contents ----------------------------------------
# The verifier enforces that ONLY tree.go may differ from this manifest; any
# other added/modified/deleted file under /app/src (test-file tampering hidden
# from git status via update-index --assume-unchanged, extra scratch files,
# edited module sources) scores 0. Generated AFTER the smoke step so the
# pristine bytes are pinned.
RUN cd /app/src \
 && find . -path ./.git -prune -o -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sed 's#  \./#  #' > /opt/golden/manifest.txt \
 && test -s /opt/golden/manifest.txt \
 && wc -l < /opt/golden/manifest.txt

# ---- open the tree for the trial uid ----------------------------------------
WORKDIR /app
COPY files/ /app/

RUN chmod -R a+rwX /app /app/src \
 && chmod 555 /opt/golden \
 && chmod 444 /opt/golden/tree_test.go /opt/golden/tree.go.parent /opt/golden/manifest.txt

CMD ["/bin/bash"]