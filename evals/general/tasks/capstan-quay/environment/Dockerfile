# capstan-quay: gohugoio/hugo issue #11406 — .RawContent of a
# front-matter-only page leaks the raw front matter.
#
# The image clones gohugoio/hugo at the PARENT commit
# a7b93e6564e6a4a7a3043b431e255ba716940408 (immediately before upstream
# commit 3a8aad6b190bb3d7cecc8ec6bc8379a01ec547cb fixed it), so the agent
# gets the real repository with the real bug still in it. hugolib/page.go
# records posMainContent (the byte offset where the body starts, i.e. where
# RawContent() begins slicing) only under `if !next.IsDone()`, so a page
# whose front matter reaches EOF leaves posMainContent at -1 and RawContent()
# falls back to offset 0 and returns the whole file including the front
# matter delimiters and keys.
#
# The clone is created with `git init` + a single `git fetch --depth 1
# origin <parent-sha>` and left detached there, so the ONLY commit object in
# /app/src/.git is the parent itself; the fix commit is unreachable. The
# golden test (the fix-commit version of hugolib/page_test.go) is extracted
# from a THROWAWAY clone that is deleted, so the fix bytes never land in the
# working clone or in this task tree.
#
# Go 1.27.1 is downloaded from go.dev. The go command's module cache
# (GOMODCACHE=$GOPATH/pkg/mod) and build cache (GOCACHE) live in the image;
# the warm pass compiles the whole hugolib test package once at build time,
# so a trial with no network can recompile incrementally in seconds.
FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA=a7b93e6564e6a4a7a3043b431e255ba716940408
ARG FIX_SHA=3a8aad6b190bb3d7cecc8ec6bc8379a01ec547cb

ENV GOPATH=/opt/gopath \
    GOCACHE=/opt/gocache \
    GOPROXY=https://proxy.golang.org \
    GO111MODULE=on \
    PATH=/usr/local/go/bin:$PATH

# ---- toolchain ----------------------------------------------------------
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build" \
 && curl -fsSL -o /tmp/go.tgz https://go.dev/dl/go1.27.1.linux-amd64.tar.gz \
 && tar -C /usr/local -xzf /tmp/go.tgz \
 && rm -f /tmp/go.tgz \
 && /usr/local/go/bin/go version

# ---- working clone: the pinned parent commit and nothing else -----------
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/gohugoio/hugo.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}" \
 && test "$(git -C /app/src rev-list --all --count)" = "1"

# ---- golden test: fix-commit version of hugolib/page_test.go ------------
# Throwaway clone, deleted afterwards. The upstream test bytes never enter
# this task tree (they only ever live at /opt/golden inside the image) and
# the fix commit never exists inside /app/src/.git.
RUN git clone --depth 1 --no-checkout https://github.com/gohugoio/hugo.git /tmp/fixsrc \
 && git -C /tmp/fixsrc fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git -C /tmp/fixsrc show ${FIX_SHA}:hugolib/page_test.go > /opt/golden/page_test.go \
 && grep -q "TestPageRawContent" /opt/golden/page_test.go \
 && grep -q "public/empty/index.html" /opt/golden/page_test.go \
 && cd / \
 && rm -rf /tmp/fixsrc

# ---- warm pass: compile the full dependency graph once, on 1 CPU ---------
# This is the layer that makes the offline trial fast: modules are fetched
# (GOPROXY/proxy.golang.org) and every package plus the hugolib test binary
# is compiled into /opt/gopath + /opt/gocache. The parent tree's own
# TestPageRawContent passes here (the parent-era test only covers pages with
# a body); the trial's tests recompile incrementally on top of this cache.
RUN cd /app/src \
 && { go test -vet=off ./hugolib -run TestPageRawContent > /tmp/warm.log 2>&1; rc=$?; \
      tail -5 /tmp/warm.log; rm -f /tmp/warm.log; test $rc -eq 0; }

# ---- the trial may run as root or as uid 1000 ----------------------------
# /app/src, the module cache, the build cache and the golden dir must all be
# usable (and for the caches, writable) by either user.
RUN chmod -R a+rwX /app/src /opt/gopath /opt/gocache /opt/golden

WORKDIR /app
COPY files/ /app/

RUN chmod -R a+rwX /app

CMD ["/bin/bash"]